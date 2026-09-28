# Native AppKit app built with SwiftPM, no Xcode project

The whole point of CloudDrop is dropping files onto a menu bar icon, which needs an AppKit `NSStatusItem` whose button accepts drags. SwiftUI's `MenuBarExtra` cannot receive drops. The Macs have Command Line Tools but no Xcode, so the app is a SwiftPM executable wrapped into a menu-bar-only `.app` bundle (`LSUIElement`) by a Makefile and signed ad-hoc. It targets macOS 26 only.

## Considered Options

- **SwiftUI `MenuBarExtra`**: rejected because it cannot receive a drop on the menu bar icon.
- **Tauri v2**: rejected (revisited 2026-09-28). Its tray icon (the `tray-icon` crate) cannot receive file drops, and the feature request tauri-apps/tauri#7894 has been open with no response since 2023. Making drops work means writing unsafe objc2 AppKit code inside a status item that Tauri owns and rebuilds, which is the same AppKit work as native Swift but more fragile. The web view, the larger bundle and the cross-platform support buy nothing for a windowless tool that runs only on Macs.
- **Electron**: rejected as far too heavy for a single-purpose personal tool.
- **Xcode project**: rejected because it would require installing Xcode on both Macs just to build a small app.

## Consequences

XCTest is not available without Xcode, so tests use Swift Testing. SwiftPM only finds it with extra `-F` and rpath flags, and without them `swift test` can run zero tests and still report success. `make test` passes the flags and fails when no tests ran.
