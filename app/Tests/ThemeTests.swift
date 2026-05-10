import SwiftUI
import AppKit
import XCTest
@testable import cc_dashboard

final class ThemeTests: XCTestCase {
    // Verifies the Claude Dark accent matches the spec orange (#d97757) within ±0.005 per channel.
    func testClaudeDarkAccentMatchesSpec() {
        let p = Themes.palette(for: .claude, mode: .dark)
        // Spec: #d97757 -> RGB (217, 119, 87) -> (0.852, 0.467, 0.341) in 0..1.
        guard let srgb = NSColor(p.accent).usingColorSpace(.sRGB) else {
            XCTFail("Could not convert accent NSColor to sRGB color space")
            return
        }
        let tolerance: CGFloat = 0.005
        XCTAssertEqual(srgb.redComponent, 0.852, accuracy: tolerance)
        XCTAssertEqual(srgb.greenComponent, 0.467, accuracy: tolerance)
        XCTAssertEqual(srgb.blueComponent, 0.341, accuracy: tolerance)
    }

    // Verifies every (ThemeId, ThemeMode) pair resolves to a palette without crashing.
    func testEveryThemeIdReturnsAPalette() {
        for id in ThemeId.allCases {
            for mode in ThemeMode.allCases {
                _ = Themes.palette(for: id, mode: mode)  // must not crash
            }
        }
    }

    // Verifies ThemeId raw values are stable for Codable round-trip (Settings persistence).
    func testThemeIdRawValuesAreStableForCodable() {
        XCTAssertEqual(ThemeId.claude.rawValue, "claude")
        XCTAssertEqual(ThemeId.tokyoNight.rawValue, "tokyoNight")
        XCTAssertEqual(ThemeId.gruvbox.rawValue, "gruvbox")
        XCTAssertEqual(ThemeId.nord.rawValue, "nord")
    }

    // Verifies all 8 palettes are now implemented after Task 23.5 (no placeholders remain).
    func testNoPlaceholdersAfterTask23_5() {
        for id in ThemeId.allCases {
            for mode in ThemeMode.allCases {
                XCTAssertFalse(Themes.isPlaceholder(id, mode), "Expected \(id)/\(mode) to be implemented after Task 23.5")
            }
        }
    }

    // Verifies each theme's dark-mode accent matches its canonical hex spec within ±0.005 per channel.
    func testThemeAccentsMatchSpec() {
        let cases: [(ThemeId, ThemeMode, CGFloat, CGFloat, CGFloat, String)] = [
            (.claude, .dark, 0.852, 0.467, 0.341, "#d97757"),
            (.tokyoNight, .dark, 0.733, 0.604, 0.969, "#bb9af7"),
            (.gruvbox, .dark, 0.980, 0.741, 0.184, "#fabd2f"),
            (.nord, .dark, 0.533, 0.753, 0.816, "#88c0d0"),
        ]
        let tolerance: CGFloat = 0.005
        for (id, mode, r, g, b, hex) in cases {
            let p = Themes.palette(for: id, mode: mode)
            guard let srgb = NSColor(p.accent).usingColorSpace(.sRGB) else {
                XCTFail("Could not convert \(id)/\(mode) accent to sRGB")
                continue
            }
            XCTAssertEqual(srgb.redComponent, r, accuracy: tolerance, "\(id)/\(mode) accent red (spec \(hex))")
            XCTAssertEqual(srgb.greenComponent, g, accuracy: tolerance, "\(id)/\(mode) accent green (spec \(hex))")
            XCTAssertEqual(srgb.blueComponent, b, accuracy: tolerance, "\(id)/\(mode) accent blue (spec \(hex))")
        }
    }

    // Verifies the 8 palettes are not all the same struct (regression guard against placeholder reintroduction).
    func testPalettesAreNotIdentical() {
        let dark = Themes.palette(for: .claude, mode: .dark)
        let nord = Themes.palette(for: .nord, mode: .dark)
        // Compare via NSColor channel of accent — easiest field to assert structural difference.
        let darkAccent = NSColor(dark.accent).usingColorSpace(.sRGB)
        let nordAccent = NSColor(nord.accent).usingColorSpace(.sRGB)
        XCTAssertNotNil(darkAccent)
        XCTAssertNotNil(nordAccent)
        XCTAssertNotEqual(darkAccent?.redComponent, nordAccent?.redComponent)
    }
}
