import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func string(_ bytes: UInt64) -> String {
        string(Int64(clamping: bytes))
    }
}
