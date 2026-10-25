# Cloudinary URL entered once and stored in the Keychain

CloudDrop needs the account's API secret to sign uploads. An app launched from Finder or at login does not inherit variables from `~/.zshrc`, so the Cloudinary URL is pasted once per Mac into a small settings window and kept in the login Keychain. Before saving, the settings window checks it with Cloudinary, including whether the key may upload. The check creates nothing.

## Considered Options

- **Reading `CLOUDINARY_URL` out of `~/.zshrc`**, as the `cloudinary-uploader` skill does: rejected. It needs no settings UI, but it couples the app to shell config files and reads the secret from a plain-text file.
- **An unsigned upload preset**, which keeps no secret on disk: rejected because anyone who learns the preset name can upload to the account, and unsigned uploads accept fewer options.

## Consequences

Builds are signed ad-hoc, so each rebuild changes the app's identity and macOS asks once more for Keychain access ("Always Allow"). This was accepted over maintaining a self-signed code-signing certificate on each Mac. Saving a new Cloudinary URL updates the Keychain item in place rather than deleting and re-adding it, so a failed save keeps the working URL; after a rebuild, that save may bring the prompt up once.
