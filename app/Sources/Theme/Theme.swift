import SwiftUI

enum ThemeId: String, CaseIterable, Codable {
    case claude, tokyoNight, gruvbox, nord
}

enum ThemeMode: String, CaseIterable, Codable {
    case dark, light
}
