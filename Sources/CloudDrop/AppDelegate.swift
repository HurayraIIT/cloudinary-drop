import AppKit
import CloudDropCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How many Captures the cleanup at quit saved to Downloads, so the next launch can say so.
    private static let capturesSavedAtQuitKey = "capturesSavedAtQuit"

    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also catches what a crash or `make install`'s pkill left, which skip applicationWillTerminate.
        let defaults = UserDefaults.standard
        let savedCaptures = TemporaryFiles.removeLeftovers() + defaults.integer(forKey: Self.capturesSavedAtQuitKey)
        defaults.removeObject(forKey: Self.capturesSavedAtQuitKey)
        NSApp.mainMenu = Self.makeMainMenu()
        LoginItem.enableOnFirstLaunch()
        statusController = StatusController()
        if savedCaptures > 0 {
            log.info("Saved \(savedCaptures, privacy: .public) unfinished Captures to Downloads")
            statusController?.reportCapturesSaved(savedCaptures)
        }
    }

    /// Quit is immediate (ADR 0004), so an Upload in progress never gets to delete its files,
    /// and Captures still in the Upload Queue are saved to Downloads.
    func applicationWillTerminate(_ notification: Notification) {
        let saved = TemporaryFiles.removeLeftovers()
        guard saved > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.capturesSavedAtQuitKey) + saved, forKey: Self.capturesSavedAtQuitKey)
    }

    /// A menu-bar-only app has no visible main menu, but without one ⌘V doesn't paste
    /// into the settings field.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit CloudDrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
