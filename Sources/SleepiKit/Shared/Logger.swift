import OSLog

/// Centralised loggers. Cheap, structured, and visible in Console.app under
/// the `co.sleepi` subsystem.
public enum Log {
    private static let subsystem = "co.sleepi"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let render = Logger(subsystem: subsystem, category: "render")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let power = Logger(subsystem: subsystem, category: "power")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let saver = Logger(subsystem: subsystem, category: "saver")
}
