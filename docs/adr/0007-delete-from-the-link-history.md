# Delete from the Link History

ADR 0004 left deleting to the Cloudinary console. In practice the mistake to fix is almost always a recent Upload, often noticed seconds after its Share Link opened, and opening the console for that is slow. So each Link History row now has a trash button that permanently Deletes the asset, from either Mac and in either public_id shape. It uses the Upload API's signed `destroy` request, not the Admin API's delete, so it doesn't spend the 500-calls-an-hour budget the Link History's search shares. It sends `invalidate=true`, so Cloudinary purges its CDN cache and the Share Link stops working within minutes rather than serving a cached copy for days. The Free plan keeps no backups, so an alert names the file first, with Cancel as the default button. A `"not found"` answer counts as success: the file is gone either way.

Search is eventually consistent, so a fetch in the seconds after a Delete can still list the asset. The Link History hides Deleted assets locally until a fetch stops listing them, for up to two minutes, mirroring how it keeps this Mac's unconfirmed Uploads. A failed Delete becomes the Last Error. The clipboard is left alone, even if it still holds the Deleted Share Link.

## Considered Options

- **Hiding the entry only**: the mistaken file would stay public.
- **Deleting without `invalidate`**: the Share Link could keep working from the CDN cache.
- **No confirmation, or a second click on the same button**: one is too easy to trigger by accident, and the other means keeping the menu open after a click, which no other row action does.
- **⌥ to turn rows into Delete items**: compact but undiscoverable.
- **Fetching right after a Delete to refill the list to ten**: an extra call that may still list the Deleted asset.
