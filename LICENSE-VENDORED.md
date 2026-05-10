# Third-party vendored components

This repository vendors the following third-party source files; the upstream
licenses apply.

## sindresorhus/KeyboardShortcuts (MIT)

- Source: https://github.com/sindresorhus/KeyboardShortcuts
- Vendored: `app/Sources/Vendored/KeyboardShortcuts/`
- Reason: replaces the global-hotkey registration stub from Loop 28 (Task 30).
  cc-dashboard does not use SwiftPM; the source files are inlined to keep the
  build hermetic.
- Subset vendored: `KeyboardShortcuts.swift`, `Name.swift`, `Shortcut.swift`,
  `Key.swift`, `HotKey.swift`, `Utilities.swift`, `ConflictPolicy.swift`,
  `Recorder.swift`, `RecorderCocoa.swift`, `ViewModifiers.swift`. The
  `NSMenuItem++.swift` file and the upstream `Localization/` `.lproj` bundles
  are intentionally NOT vendored — cc-dashboard does not have a main menu that
  participates in shortcut conflict checks, and English source-locale strings
  are inlined in `Utilities.swift` in place of the localized resources.
- Local modifications: each vendored file's leading comment block lists the
  modifications applied at copy time. Summary:
  - `Utilities.swift`: `String.localized` resolves keys via a literal
    `[String: String]` dictionary mirroring upstream's
    `Localization/en.lproj/Localizable.strings` (added Loop 32). Unknown keys
    fall through to `self`. Both `LocalEventMonitor.deinit` and
    `RunLoopLocalEventMonitor.deinit` had `isolated` dropped (Swift 6.1
    experimental feature, not enabled in this project's Swift 5 mode).
  - `Shortcut.swift`: `SpecialKey.presentableDescription` for `.space` is
    the literal string `"Space"` rather than `"space_key".localized.capitalized`.
  - `HotKey.swift`: `HotKey.deinit` had `isolated` dropped.
  - `KeyboardShortcuts.swift`: `repeatingKeyDownEvents(for name:)` annotated
    `@MainActor` so it can construct the inner `@MainActor` `RepeatState`
    class — the upstream relied on package-wide `defaultIsolation(MainActor.self)`
    which Swift 5 mode does not apply.
  - `Recorder.swift`: dropped the three `#Preview { ... }` blocks at the
    file foot (debug-only, would render localization keys literally without
    a `.strings` file in the bundle and add no test value).
  - `RecorderCocoa.swift`: `RecorderCocoa.deinit` had `isolated` dropped.
    Seven `.localized` call sites resolve via the dictionary in
    `Utilities.swift`.
  - `ViewModifiers.swift`: no modifications.

### Upstream MIT license text

```
MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
