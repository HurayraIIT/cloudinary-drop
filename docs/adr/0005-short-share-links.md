# Short Share Links: random names, built from the public_id

Share Links used to be Cloudinary's `secure_url`, with a timestamp, random suffix and slugged filename (112 characters for a screenshot). Now each Upload gets a random 8-character `a-z0-9` name in a one-letter URL folder, `d/k3f9x2ab`, and CloudDrop builds the link itself. There is no version segment, and images use Cloudinary's root path form, which drops `/image/upload`. The result is `https://res.cloudinary.com/<cloud>/d/k3f9x2ab.png`, 51 characters. Videos must keep `/video/upload/`, because Cloudinary's root path form only works for images. This also keeps the original filename out of public links. Instead it goes to the console as `display_name`, and the console folder (`asset_folder`) stays `clouddrop`, separate from the URL path.

Dropping the version is only safe because a name is never reused. A signed upload overwrites by default, and a live test showed that an overwrite serves the new bytes even at the old versioned URL. So Uploads send `overwrite=false` and treat Cloudinary's `"existing": true` reply, which is an HTTP 200, as a failed Upload. We don't pick a new name and upload again, because ADR 0004 rules out retries and this is vanishingly rare.

## Considered Options

- **A date plus 6 random characters (`260929_k3f9x2`)**: sorts by day, but costs 5 characters and reveals the upload date.
- **No URL folder**: 2 characters shorter, but mixes CloudDrop's uploads with anything else in the account.
- **A custom domain or private CDN**: needs Cloudinary's Advanced plan.
- **A link shortener**: another cloud service, which ADR 0004 rules out.
