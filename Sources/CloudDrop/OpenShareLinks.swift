import Foundation

/// The Settings submenu's Open Share Links in Browser toggle, saved on this Mac only. Read as each Upload
/// succeeds, so turning it off mid-queue stops the tabs that haven't opened yet. The clipboard is always set.
@MainActor
enum OpenShareLinks {
    private static let key = "openShareLinks"

    /// On by default.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
