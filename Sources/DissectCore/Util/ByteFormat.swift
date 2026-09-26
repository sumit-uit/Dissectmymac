import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
        return formatter.string(fromByteCount: bytes)
    }

    public static func string(_ bytes: UInt64) -> String {
        string(Int64(clamping: bytes))
    }
}
