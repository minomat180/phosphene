import Foundation
import IOKit.pwr_mgt
import os

/// Keeps the display on while the screen is locked, so the lock screen video stays
/// visible. Without it, macOS turns a locked display off after about 30 seconds,
/// regardless of the "turn display off when inactive" setting.
///
/// The assertion lasts until unlock or until the user's own display sleep time has
/// passed, whichever comes first, so a locked Mac goes dark when an unlocked one would.
/// It only prevents display sleep, never system sleep, and is skipped while playback is
/// paused (the lock screen would show a still frame).
@MainActor
enum LockScreenAwake {
    private static let logger = Logger(subsystem: "io.github.minomat180.phosphene", category: "LockScreenAwake")
    private static var assertionID: IOPMAssertionID?
    private static var releaseTask: Task<Void, Never>?

    /// Start following the lock state. Call once at launch.
    static func listen() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { locked() }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { release(reason: "unlocked") }
        }
    }

    private static func locked() {
        guard !WallpaperPrefsService.shared.userPaused else { return }
        release(reason: "relocked")
        let minutes = displaySleepMinutes()
        var id = IOPMAssertionID(0)
        let result = unsafe IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Phosphene keeps the lock screen video visible" as CFString,
            &id,
        )
        guard result == kIOReturnSuccess else {
            logger.error("Could not hold the display on: \(result)")
            return
        }
        assertionID = id
        logger.info("Holding the display on while locked (\(minutes == 0 ? "until unlock" : "\(minutes) min", privacy: .public))")
        // 0 means the user never lets the display sleep: hold until unlock.
        guard minutes > 0 else { return }
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            release(reason: "display sleep time reached")
        }
    }

    private static func release(reason: String) {
        releaseTask?.cancel()
        releaseTask = nil
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
        logger.info("Released the display (\(reason, privacy: .public))")
    }

    /// The display sleep time in use (for the current power source), in minutes,
    /// 0 meaning never. Read from `pmset -g`; falls back to 10 minutes.
    private static func displaySleepMinutes() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return 10 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        for line in (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 2, fields[0] == "displaysleep", let minutes = Int(fields[1]) {
                return minutes
            }
        }
        return 10
    }
}
