# Signed uploads go straight from the app to Cloudinary

Each Media File is uploaded directly from the Mac to Cloudinary's upload API, signed with the Cloudinary URL's secret. There is no server, proxy or cloud function in between. As a result, the account's Free-plan size limits (10 MB per image, 100 MB per video as of 2026-09) are checked on the Mac before uploading, and a file over its limit is refused rather than shrunk. Videos are now compressed on the Mac first, and the limit is checked on the compressed file ([ADR 0008](0008-compress-videos-before-upload.md)). Files are never chunked, because 100 MB is already the plan's per-file maximum.

## Consequences

If the Cloudinary plan changes, the size limits in the app must be updated to match.
