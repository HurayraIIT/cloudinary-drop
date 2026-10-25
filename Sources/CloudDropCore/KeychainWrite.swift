import Security

/// Saving the Cloudinary URL over the one already in the Keychain (ADR 0002). The old item is updated in place,
/// never deleted first, so a write that fails leaves the working Cloudinary URL where it was.
public enum KeychainWrite {
    /// `update` changes the existing item. `add` creates one, and runs only when there's no item to update.
    public static func save(update: () -> OSStatus, add: () -> OSStatus) -> OSStatus {
        let status = update()
        return status == errSecItemNotFound ? add() : status
    }
}
