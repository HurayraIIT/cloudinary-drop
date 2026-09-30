# The Link History comes from Cloudinary

The Link History used to be an in-memory list of this Mac's Uploads, lost on quit. With two Macs, an Upload from one never showed on the other. Now the Link History is the 10 newest assets in the `clouddrop` asset folder, fetched with Cloudinary's Search API (sorted by `created_at`, one call for images and videos together). The menu shows the list it already has straight away and refreshes it in the background, at most every 30 seconds and once at launch, because the Admin API allows 500 calls an hour, shared by both Macs and any other tool using the key. A rate limit pauses refreshes until Cloudinary's reset time. Nothing is written to disk: the list, and thumbnails fetched through an ephemeral session, live only in memory. Search takes a few seconds to list a new asset, so this Mac's own Uploads are added locally at once and kept until a fetch lists them, or until a fetch that starts two minutes later still doesn't, which means the asset is gone.

Uploads from the other Mac have no local file to make a thumbnail from, so image rows use a 44 px square `c_fill` thumbnail from Cloudinary. This is the only transformation outside HEIC→JPG. It costs one transformation per image, once, and it never appears in a Share Link. Videos keep the `film` symbol. Saving a Cloudinary URL also checks that the key may search. A key that can't is still saved, with a warning, because uploading is what matters.

## Considered Options

- **Merging the local list with the remote one, or showing them as two sections**: two sources that can disagree, for no gain once the account is the source of truth.
- **Fetching only on a timer or after Uploads, never when the menu opens**: fewer calls, but the other Mac's Uploads would show up late.
- **Every asset in the account**: the account holds hundreds of files from another tool, which would bury CloudDrop's.
- **Saving the list to disk for offline launches**: a cache that can go stale, to save one fetch.
- **No thumbnails for remote rows**: rows from the two Macs would look different.
