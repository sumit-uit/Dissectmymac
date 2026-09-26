import AppKit
import DissectCore
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, forest, ocean, aurora

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var isPremium: Bool { self != .system }

    var accent: Color {
        switch self {
        case .system: return .accentColor
        case .forest: return Color(red: 0.20, green: 0.55, blue: 0.33)
        case .ocean: return Color(red: 0.10, green: 0.45, blue: 0.75)
        case .aurora: return Color(red: 0.55, green: 0.30, blue: 0.85)
        }
    }

    /// Colors cycled through for folders in the storage map.
    var palette: [Color] {
        switch self {
        case .system:
            return [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red, .cyan, .mint]
        case .forest:
            return [0x2D6A4F, 0x40916C, 0x52B788, 0x74C69D, 0x1B4332, 0x95D5B2, 0x6A994E, 0xA7C957, 0x386641, 0x588157]
                .map(Color.init(hex:))
        case .ocean:
            return [0x03045E, 0x023E8A, 0x0077B6, 0x0096C7, 0x00B4D8, 0x48CAE4, 0x1D3557, 0x457B9D, 0x006D77, 0x83C5BE]
                .map(Color.init(hex:))
        case .aurora:
            return [0x7400B8, 0x6930C3, 0x5E60CE, 0x5390D9, 0x4EA8DE, 0x48BFE3, 0x56CFE1, 0x64DFDF, 0x72EFDD, 0x80FFDB]
                .map(Color.init(hex:))
        }
    }

    func color(for category: FileCategory) -> Color {
        switch category {
        case .video: return palette[0]
        case .audio: return palette[1]
        case .images: return palette[2]
        case .documents: return palette[3]
        case .archives: return palette[4]
        case .diskImages: return palette[5]
        case .code: return palette[6]
        case .apps: return palette[7]
        case .other: return .gray
        }
    }
}

extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
