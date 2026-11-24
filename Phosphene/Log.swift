import os

enum Log {
    static let general = Logger(subsystem: "io.github.minomat180.phosphene", category: "General")
    static let video = Logger(subsystem: "io.github.minomat180.phosphene", category: "Video")
    static let storage = Logger(subsystem: "io.github.minomat180.phosphene", category: "Storage")
    static let login = Logger(subsystem: "io.github.minomat180.phosphene", category: "LaunchAtLogin")
    static let update = Logger(subsystem: "io.github.minomat180.phosphene", category: "Update")
}
