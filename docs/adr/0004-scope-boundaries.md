# Deliberately out of scope

CloudDrop does one thing: it turns image and video files dropped on its icon into Share Links. These were considered and explicitly left out to keep it minimal:
- renaming uploads (use the Cloudinary console). Deleting was here too until [ADR 0007](0007-delete-from-the-link-history.md) brought it back in scope
- Cloudinary transformations, except that HEIC links are delivered as JPEG and the Link History's image thumbnails ([ADR 0006](0006-link-history-from-cloudinary.md)). Compressing videos on the Mac before uploading isn't a Cloudinary transformation, and is in scope since [ADR 0008](0008-compress-videos-before-upload.md)
- any other cloud service
- Link History written to disk (it's fetched from Cloudinary instead, see ADR 0006)
- browser drags, clipboard images and non-media files
- auto-update
- a Dock icon
- retrying failed Uploads
- asking for confirmation before quitting mid-queue

The menu's one-line Usage summary (counts, storage, credits) is in scope, though: it is read-only and cheap on the hourly API limit. So is the menu's Settings submenu: Open Share Links in Browser, the Compress Videos toggle and its Quality Levels (ADR 0008), and Launch at Login. Together with the Cloudinary URL, they're the only settings. Opening each Share Link stays on by default; turning it off is for a Mac where a burst of tabs gets in the way, and the clipboard is still set either way. They're grouped in a submenu so the top level stays the Link History, the Usage line, Set Cloudinary URL… and Quit.

Before adding any of these, revisit this decision.
