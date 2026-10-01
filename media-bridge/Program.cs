using System.Diagnostics;
using System.Text.Json;
using Windows.Media.Control;

internal static class Program
{
    private static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Length == 0) return 2;
            var mode = args[0].ToLowerInvariant();
            if (mode == "watch" && args.Length >= 3)
                return await WatchAsync(args[1], int.TryParse(args[2], out var parent) ? parent : 0);
            if (mode == "command" && args.Length >= 2)
                return await CommandAsync(args[1].ToLowerInvariant());
            if (mode == "snapshot")
            {
                var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
                Console.WriteLine(JsonSerializer.Serialize(await ReadSnapshotAsync(manager)));
                return 0;
            }
            return 2;
        }
        catch
        {
            return 1;
        }
    }

    private static async Task<int> WatchAsync(string outputPath, int parentPid)
    {
        using var mutex = new Mutex(false, "Local\\LiveCaptionsMediaBridgeWatcher");
        try { if (!mutex.WaitOne(0)) return 0; }
        catch (AbandonedMutexException) { }

        var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        var tempPath = outputPath + ".tmp";
        while (ParentIsAlive(parentPid))
        {
            try
            {
                var snapshot = await ReadSnapshotAsync(manager);
                Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
                await File.WriteAllTextAsync(tempPath, JsonSerializer.Serialize(snapshot));
                File.Move(tempPath, outputPath, true);
            }
            catch
            {
                try { File.Delete(tempPath); } catch { }
            }
            await Task.Delay(750);
        }
        try { File.Delete(outputPath); } catch { }
        return 0;
    }

    private static bool ParentIsAlive(int parentPid)
    {
        if (parentPid <= 0) return true;
        try { return !Process.GetProcessById(parentPid).HasExited; }
        catch { return false; }
    }

    private static async Task<int> CommandAsync(string command)
    {
        var manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        var session = manager.GetCurrentSession();
        if (session is null) return 3;
        var succeeded = command switch
        {
            "previous" => await session.TrySkipPreviousAsync(),
            "toggle" => await session.TryTogglePlayPauseAsync(),
            "next" => await session.TrySkipNextAsync(),
            _ => false
        };
        return succeeded ? 0 : 4;
    }

    private static async Task<Snapshot> ReadSnapshotAsync(GlobalSystemMediaTransportControlsSessionManager manager)
    {
        var session = manager.GetCurrentSession();
        if (session is null) return new Snapshot(false, "", "", "", "", "", false, false, false);

        var properties = await session.TryGetMediaPropertiesAsync();
        var playback = session.GetPlaybackInfo();
        var controls = playback.Controls;
        var appId = session.SourceAppUserModelId ?? "";
        return new Snapshot(
            true,
            appId,
            FriendlyAppName(appId),
            properties.Title ?? "",
            properties.Artist ?? "",
            playback.PlaybackStatus.ToString(),
            controls.IsPreviousEnabled,
            controls.IsPlayPauseToggleEnabled,
            controls.IsNextEnabled);
    }

    private static string FriendlyAppName(string appId)
    {
        if (appId.Contains("chrome", StringComparison.OrdinalIgnoreCase)) return "Google Chrome";
        if (appId.Contains("msedge", StringComparison.OrdinalIgnoreCase) || appId.Contains("MicrosoftEdge", StringComparison.OrdinalIgnoreCase)) return "Microsoft Edge";
        if (appId.Contains("spotify", StringComparison.OrdinalIgnoreCase)) return "Spotify";
        if (appId.Contains("firefox", StringComparison.OrdinalIgnoreCase)) return "Mozilla Firefox";
        if (appId.Contains("vlc", StringComparison.OrdinalIgnoreCase)) return "VLC media player";
        return appId;
    }

    private sealed record Snapshot(
        bool HasSession,
        string AppId,
        string AppName,
        string Title,
        string Artist,
        string PlaybackStatus,
        bool CanPrevious,
        bool CanToggle,
        bool CanNext);
}
