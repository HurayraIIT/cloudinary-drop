# Deliberately out of scope

CloudDrop does one thing: it turns image and video files dropped on its icon into Share Links. These were considered and explicitly left out to keep it minimal:
- renaming uploads (use the Cloudinary console). Deleting was here too until [ADR 0007](0007-delete-from-the-link-history.md) brought it back in scope
- transformations, except that HEIC links are delivered as JPEG and the Link History's image thumbnails ([ADR 0006](0006-link-history-from-cloudinary.md))
- any other cloud service
- Link History written to disk (it's fetched from Cloudinary instead, see ADR 0006)
- browser drags, clipboard images and non-media files
- auto-update
- a Dock icon
- retrying failed Uploads
- asking for confirmation before quitting mid-queue

Before adding any of these, revisit this decision.
