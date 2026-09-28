# Deliberately out of scope

CloudDrop does one thing: it turns image and video files dropped on its icon into Share Links. These were considered and explicitly left out to keep it minimal:
- deleting or renaming uploads (use the Cloudinary console)
- transformations, except that HEIC links are delivered as JPEG
- any other cloud service
- Link History that survives a restart
- browser drags, clipboard images and non-media files
- auto-update
- a Dock icon
- retrying failed Uploads
- asking for confirmation before quitting mid-queue

Before adding any of these, revisit this decision.
