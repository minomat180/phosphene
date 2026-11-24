import Foundation
import os

/// `phosphene://` commands for scripts and agents, so everything the menu bar does can be
/// done from a shell (see `scripts/phosphenectl`). They arrive as the object of the
/// distributed notification ``notificationName``: SwiftUI hands `open phosphene://…` to its
/// scenes rather than to the app delegate, so a URL opened that way never gets here.
///
/// - `phosphene://desktop?path=/abs/file` shows an image or video on the desktop and plays
///   the wallpaper video only on the lock screen. `phosphene://desktop/clear` removes it.
/// - `phosphene://playback?scope=everywhere|lockscreen|paused`
/// - `phosphene://add-video?path=/abs/file[&name=Title]` adds a video to the library
///   (without `path`, it opens the file chooser as before).
/// - `phosphene://restart-agent` restarts WallpaperAgent.
///
/// Each command writes its outcome to `agent-result.json` in the extension's container,
/// next to `phosphene-prefs.json` and `phosphene-state.json`.
@MainActor
enum AgentCommands {
    private static let logger = Logger(subsystem: "io.github.minomat180.phosphene", category: "AgentCommands")

    static let notificationName = Notification.Name("io.github.minomat180.phosphene.command")

    /// Start taking commands. Call once at launch.
    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { note in
            guard let text = note.object as? String, let url = URL(string: text), url.scheme == "phosphene" else { return }
            Task { @MainActor in
                if await !handle(url) {
                    report(text, ok: false, "Unknown command.")
                }
            }
        }
    }

    private struct Result: Encodable {
        let command: String
        let ok: Bool
        let message: String
        let date: Date
    }

    /// Handle `url` if it is an agent command. Returns false for anything else.
    static func handle(_ url: URL) async -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last },
        )
        let prefs = WallpaperPrefsService.shared
        let command = [url.host ?? "", url.path].joined()

        switch (url.host, url.path) {
        case ("desktop", "/clear"):
            prefs.clearDesktopSource()
            report(command, ok: true, "Desktop shows the paused video.")
        case ("desktop", _):
            guard let path = query["path"], !path.isEmpty else {
                report(command, ok: false, "Missing path."); return true
            }
            let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            do {
                try prefs.setDesktopSource(from: file)
                report(command, ok: true, "Desktop shows \(file.lastPathComponent); the video plays on the lock screen.")
            } catch {
                report(command, ok: false, error.localizedDescription)
            }
        case ("playback", _):
            switch query["scope"]?.lowercased() {
            case "everywhere":
                prefs.userPaused = false
                prefs.alwaysPauseDesktop = false
            case "lockscreen", "lock-screen":
                prefs.userPaused = false
                prefs.alwaysPauseDesktop = true
            case "paused":
                prefs.userPaused = true
                prefs.alwaysPauseDesktop = false
            default:
                report(command, ok: false, "scope must be everywhere, lockscreen or paused."); return true
            }
            report(command, ok: true, "Playback: \(query["scope"] ?? "").")
        case ("add-video", _):
            guard let path = query["path"], !path.isEmpty else { return false }
            let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.isReadableFile(atPath: file.path) else {
                report(command, ok: false, "Cannot read \(file.path)."); return true
            }
            if let id = await VideoDeploymentService.deployVideo(url: file, name: query["name"]) {
                report(command, ok: true, "Added \(file.lastPathComponent) as \(id). Choose it in System Settings > Wallpaper.")
            } else {
                report(command, ok: false, "Not added: \(file.lastPathComponent) is already in the library or could not be copied.")
            }
        case ("restart-agent", _):
            prefs.restartWallpaperAgent()
            report(command, ok: true, "WallpaperAgent restarted.")
        default:
            return false
        }
        return true
    }

    private static func report(_ command: String, ok: Bool, _ message: String) {
        if ok {
            logger.info("\(command, privacy: .public): \(message, privacy: .public)")
        } else {
            logger.error("\(command, privacy: .public) failed: \(message, privacy: .public)")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Result(command: command, ok: ok, message: message, date: Date())) else { return }
        try? data.write(to: WallpaperPrefsService.extensionDocumentsURL.appendingPathComponent("agent-result.json"), options: .atomic)
    }
}
