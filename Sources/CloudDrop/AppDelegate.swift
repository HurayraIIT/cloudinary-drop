import AppKit
import CloudDropCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// How many Captures the cleanup at quit saved to Downloads, so the next launch can say so.
    private static let capturesSavedAtQuitKey = "capturesSavedAtQuit"

    private var statusController: StatusController?
    private var terminationSignal: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOnSIGTERM()
        // Also catches what a crash or a forced kill left, which skip applicationWillTerminate. Captures it
        // couldn't save at the last quit are still in their folders, so they're tried again here.
        let defaults = UserDefaults.standard
        var captures = TemporaryFiles.removeLeftovers()
        captures.saved += defaults.integer(forKey: Self.capturesSavedAtQuitKey)
        defaults.removeObject(forKey: Self.capturesSavedAtQuitKey)
        NSApp.mainMenu = Self.makeMainMenu()
        LoginItem.enableOnFirstLaunch()
        statusController = StatusController()
        if let message = TemporaryFiles.leftoverCapturesMessage(captures) {
            log.info("Leftover Captures: \(captures.saved, privacy: .public) saved to Downloads, \(captures.unsaved, privacy: .public) couldn't be")
            statusController?.reportLeftoverCaptures(message)
        }
    }

    /// `make install` and `make uninstall` send SIGTERM, which would otherwise kill the app on the spot, leaving ffmpeg
    /// running and skipping applicationWillTerminate. Quitting normally stops ffmpeg and saves waiting Captures.
    private func quitOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }

    /// Quit is immediate (ADR 0004), so an Upload in progress never gets to delete its files,
    /// and Captures still in the Upload Queue are saved to Downloads. ffmpeg is stopped first,
    /// so it isn't left running, and its partial output is swept away.
    func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
        // Captures that couldn't be saved stay in their folders for the next launch, which reports them.
        let saved = TemporaryFiles.removeLeftovers().saved
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
