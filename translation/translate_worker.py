import ctypes
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from pathlib import Path

request_path = Path(sys.argv[1])
response_path = Path(sys.argv[2])
parent_pid = int(sys.argv[3])
default_model_root = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "TransparentLiveCaptions" / "models"
model_root = Path(sys.argv[4]) if len(sys.argv) > 4 and str(sys.argv[4]).strip() else Path(os.environ.get("TLC_MODEL_ROOT", default_model_root))

nllb_model_path = model_root / "models" / "nllb-int8"
hy_model_path = model_root / "models" / "hy-mt2-1.8b-q4" / "Hy-MT2-1.8B-Q4_K_M.gguf"
llama_server_path = model_root / "runtimes" / "llama-b11284" / "llama-server.exe"

HY_ALIAS = "hy-mt2-live"
HY_PORT_RANGE = range(18792, 18800)
HY_REQUEST_TIMEOUT_SECONDS = 1.8
CONTEXT_IDLE_RESET_SECONDS = 15.0
MAX_CONTEXT_SENTENCES = 1


def parent_is_alive(pid: int) -> bool:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle = kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    try:
        exit_code = ctypes.c_ulong()
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
            return False
        return exit_code.value == 259
    finally:
        kernel32.CloseHandle(handle)


def detect_language(text: str, previous_source: str | None = None) -> str:
    if re.search(r"[\u3040-\u30ff]", text):
        return "ja"
    if re.search(r"[\uac00-\ud7af]", text):
        return "ko"
    latin = len(re.findall(r"[A-Za-z]", text))
    han = len(re.findall(r"[\u3400-\u9fff]", text))
    if previous_source == "ja" and han and latin <= 8:
        return "ja"
    if han and not latin:
        return "zh"
    if latin:
        return "en"
    return "unknown"


def atomic_json_write(path: Path, data: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(temp, path)


def split_translation_units(text: str) -> list[str]:
    units = [
        match.group(0).strip()
        for match in re.finditer(r".+?(?:[。！？.!?…]+|$)", text, flags=re.S)
        if match.group(0).strip()
    ]
    return units or [text]


def completed_sentence_units(text: str) -> list[str]:
    return [
        match.group(0).strip()
        for match in re.finditer(r".+?[。！？.!?…]+", text, flags=re.S)
        if match.group(0).strip()
    ]


def translate_nllb(translator, sentencepiece, text: str, source: str) -> str:
    source_code = {"ja": "jpn_Jpan", "en": "eng_Latn"}[source]
    units = split_translation_units(text)
    tokens = [
        [source_code] + sentencepiece.encode(unit, out_type=str) + ["</s>"]
        for unit in units
    ]
    results = translator.translate_batch(
        tokens,
        target_prefix=[["zho_Hans"]] * len(tokens),
        beam_size=4,
        max_decoding_length=160,
    )
    translated = [
        sentencepiece.decode(result.hypotheses[0][1:]).strip()
        for result in results
    ]
    return "".join(part for part in translated if part)



class NLLBFallback:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.translator = None
        self.sentencepiece = None

    def ensure_loaded(self) -> None:
        if self.translator is not None and self.sentencepiece is not None:
            return
        with self._lock:
            if self.translator is not None and self.sentencepiece is not None:
                return
            import ctranslate2
            import sentencepiece as spm

            translator = ctranslate2.Translator(
                str(nllb_model_path),
                device="cpu",
                compute_type="int8",
                inter_threads=1,
                intra_threads=4,
            )
            sentencepiece = spm.SentencePieceProcessor(
                model_file=str(nllb_model_path / "sentencepiece.bpe.model")
            )
            translate_nllb(translator, sentencepiece, "Hello", "en")
            translate_nllb(translator, sentencepiece, "こんにちは", "ja")
            self.translator = translator
            self.sentencepiece = sentencepiece

    def translate(self, text: str, source: str) -> str:
        self.ensure_loaded()
        return translate_nllb(self.translator, self.sentencepiece, text, source)

def hidden_startupinfo():
    if os.name != "nt":
        return None
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    info.wShowWindow = 0
    return info


def hidden_creationflags() -> int:
    return getattr(subprocess, "CREATE_NO_WINDOW", 0)


def stop_stale_hy_servers() -> None:
    """Remove only prior llama-server processes started with this exact model."""
    if os.name != "nt":
        return
    model_name = hy_model_path.name.replace("'", "''")
    script = (
        "$name='" + model_name + "';"
        "Get-CimInstance Win32_Process -Filter \"Name = 'llama-server.exe'\" "
        "-ErrorAction SilentlyContinue | "
        "Where-Object { $_.CommandLine -and $_.CommandLine -like ('*' + $name + '*') } | "
        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
    )
    try:
        subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command", script],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4,
            creationflags=hidden_creationflags(),
            startupinfo=hidden_startupinfo(),
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def choose_loopback_port() -> int:
    for port in HY_PORT_RANGE:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.settimeout(0.1)
            try:
                probe.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


class HyMT2Client:
    def __init__(self) -> None:
        self.process: subprocess.Popen | None = None
        self.port: int | None = None
        self.consecutive_failures = 0

    @property
    def available(self) -> bool:
        return llama_server_path.is_file() and hy_model_path.is_file()

    def _url(self, suffix: str) -> str:
        if self.port is None:
            raise RuntimeError("Hy-MT2 server has no port")
        return f"http://127.0.0.1:{self.port}{suffix}"

    def _health_ok(self, timeout: float = 0.25) -> bool:
        if self.process is not None and self.process.poll() is not None:
            return False
        if self.port is None:
            return False
        try:
            with urllib.request.urlopen(self._url("/health"), timeout=timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return payload.get("status") == "ok"
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            return False

    def start(self, wait_seconds: float = 12.0) -> bool:
        if not self.available:
            return False
        if self._health_ok():
            return True
        if self.process is not None and self.process.poll() is None and self.port is not None:
            return self._wait_ready(wait_seconds)

        self.stop()
        self.port = choose_loopback_port()
        args = [
            str(llama_server_path),
            "-m",
            str(hy_model_path),
            "--alias",
            HY_ALIAS,
            "--host",
            "127.0.0.1",
            "--port",
            str(self.port),
            "-ngl",
            "99",
            "-c",
            "2048",
            "-np",
            "1",
        ]
        try:
            self.process = subprocess.Popen(
                args,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=hidden_creationflags(),
                startupinfo=hidden_startupinfo(),
            )
        except OSError:
            self.process = None
            return False

        return self._wait_ready(wait_seconds)

    def _wait_ready(self, wait_seconds: float) -> bool:
        deadline = time.monotonic() + max(0.0, wait_seconds)
        while time.monotonic() < deadline:
            if self.process is not None and self.process.poll() is not None:
                return False
            if self._health_ok(timeout=0.35):
                return True
            time.sleep(0.15)
        return self._health_ok(timeout=0.35)

    def stop(self) -> None:
        process = self.process
        self.process = None
        if process is None:
            return
        if process.poll() is None:
            try:
                process.terminate()
                process.wait(timeout=1.2)
            except (OSError, subprocess.SubprocessError):
                try:
                    process.kill()
                except OSError:
                    pass

    def _chat(self, prompt: str, timeout: float) -> str:
        payload = json.dumps(
            {
                "model": HY_ALIAS,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 160,
                "temperature": 0.0,
                "top_p": 0.6,
                "seed": 42,
            },
            ensure_ascii=False,
        ).encode("utf-8")
        request = urllib.request.Request(
            self._url("/v1/chat/completions"),
            data=payload,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8"))
        text = str(data["choices"][0]["message"]["content"]).strip()
        if not text:
            raise RuntimeError("Hy-MT2 returned an empty translation")
        return text

    def warm(self) -> None:
        if not self._health_ok(timeout=0.35):
            return
        try:
            self._chat(
                "将以下文本翻译为简体中文，注意只需要输出翻译后的结果，不要额外解释：\nこんにちは。",
                timeout=3.0,
            )
        except Exception:
            pass

    def translate(self, prompt: str) -> str:
        if not self._health_ok(timeout=0.2):
            if not self.start(wait_seconds=0.65):
                raise RuntimeError("Hy-MT2 server unavailable")
        try:
            result = self._chat(prompt, timeout=HY_REQUEST_TIMEOUT_SECONDS)
            self.consecutive_failures = 0
            return result
        except Exception:
            self.consecutive_failures += 1
            if self.consecutive_failures >= 2:
                self.stop()
                self.start(wait_seconds=0.15)
                self.consecutive_failures = 0
            raise


def build_hy_prompt(text: str, context_sentences: list[str]) -> str:
    if context_sentences:
        context = "\n".join(context_sentences[-MAX_CONTEXT_SENTENCES:])
        return (
            f"上文：{context}\n"
            f"当前字幕：{text}\n"
            "请结合上文语境，把“当前字幕”自然翻译成简体中文。"
            "只输出当前字幕的译文，不要翻译上文，不要解释。"
        )
    return (
        "将以下文本翻译为简体中文，注意只需要输出翻译后的结果，不要额外解释：\n"
        f"{text}"
    )


def clean_translation(text: str) -> str:
    text = text.strip()
    if text.startswith("```") and text.endswith("```"):
        text = re.sub(r"^```[^\n]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
    text = re.sub(r"^(?:当前字幕|译文|翻译结果)\s*[:：]\s*", "", text).strip()
    text = text.replace("⁇", "…").replace("�", "…")
    text = re.sub(r"…+", "…", text)
    text = re.sub(r"\s+([，。？！；：,.!?])", r"\1", text)
    return text.strip()


def context_for_text(
    histories: dict[str, deque[str]], source: str, text: str
) -> list[str]:
    if source not in histories:
        return []
    selected = []
    for sentence in reversed(histories[source]):
        if sentence and sentence not in text and text not in sentence:
            selected.append(sentence)
        if len(selected) >= MAX_CONTEXT_SENTENCES:
            break
    selected.reverse()
    return selected


def remember_completed(
    histories: dict[str, deque[str]], source: str, text: str
) -> None:
    if source not in histories:
        return
    history = histories[source]
    for sentence in completed_sentence_units(text):
        if len(sentence) < 2:
            continue
        if history and history[-1] == sentence:
            continue
        if sentence in history:
            try:
                history.remove(sentence)
            except ValueError:
                pass
        history.append(sentence)


def main() -> None:
    stop_stale_hy_servers()

    # Load the primary engine once at startup. Trying to translate with NLLB
    # while the 1.13 GB GPU model is loading caused multi-second contention;
    # a short one-time startup is smoother than repeated stalls.
    hy = HyMT2Client()
    hy_started = hy.start(wait_seconds=12.0)
    if hy_started:
        hy.warm()

    # Keep NLLB hot only as a runtime fallback after the primary is ready.
    nllb = NLLBFallback()
    threading.Thread(target=nllb.ensure_loaded, daemon=True).start()

    histories: dict[str, deque[str]] = {
        "ja": deque(maxlen=6),
        "en": deque(maxlen=6),
    }
    seen_id = None
    pending = None
    changed_at = 0.0
    last_source = None
    last_activity = time.monotonic()

    try:
        while parent_is_alive(parent_pid):
            try:
                with request_path.open("r", encoding="utf-8-sig") as stream:
                    request = json.load(stream)
                if request.get("id") != seen_id:
                    pending = request
                    seen_id = request.get("id")
                    changed_at = time.monotonic()
            except (FileNotFoundError, PermissionError, json.JSONDecodeError):
                pass

            if pending and time.monotonic() - changed_at >= 0.18:
                current = pending
                pending = None
                text = str(current.get("text", "")).strip()
                source = detect_language(text, last_source)
                if source in ("ja", "en", "zh"):
                    last_source = source

                now = time.monotonic()
                if now - last_activity >= CONTEXT_IDLE_RESET_SECONDS:
                    for history in histories.values():
                        history.clear()
                last_activity = now

                started = time.monotonic()
                engine = ""
                fallback = False
                context_sentences: list[str] = []
                try:
                    if source == "zh":
                        result, error, engine = text, "", "passthrough"
                    elif source in ("ja", "en"):
                        context_sentences = context_for_text(histories, source, text)
                        prompt = build_hy_prompt(text, context_sentences)
                        if hy_started:
                            try:
                                result = hy.translate(prompt)
                                engine = "hy-mt2"
                            except Exception:
                                result = nllb.translate(text, source)
                                engine = "nllb"
                                fallback = True
                        else:
                            result = nllb.translate(text, source)
                            engine = "nllb"
                            fallback = True
                        error = ""
                        remember_completed(histories, source, text)
                    else:
                        result, error, engine = "", "暂不支持识别这种字幕语言", "none"

                    if result:
                        result = clean_translation(result)
                except Exception:
                    result, error, engine = "", "离线翻译暂时不可用", "error"

                atomic_json_write(
                    response_path,
                    {
                        "id": current.get("id"),
                        "source": source,
                        "text": text,
                        "translation": result,
                        "error": error,
                        "engine": engine,
                        "fallback": fallback,
                        "context_sentences": len(context_sentences),
                        "latency_ms": int((time.monotonic() - started) * 1000),
                    },
                )
            time.sleep(0.08)
    finally:
        hy.stop()
        for path in (request_path, response_path):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        try:
            atomic_json_write(
                response_path,
                {"id": -1, "error": "离线翻译引擎启动失败", "engine": "error"},
            )
        except Exception:
            pass