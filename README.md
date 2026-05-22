# Nix

Private Microsoft Store app archive template powered by GitHub Actions.

Nix checks a Microsoft Store product through the DanStore API, picks the newest suitable package, and archives new builds as private GitHub Release assets. It is designed for personal backup workflows where the generated archive repository should stay private.

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/bceea57b5a3ae5d1f5afae384a8494ccc575e27a.svg "Repobeats analytics image")

> [!IMPORTANT]
> This project does not grant permission to redistribute Microsoft Store apps, installers, packages, or binaries. Keep generated archive repositories private unless you are certain you have the right to publish the archived files.

## What It Does

- Resolves the latest package metadata for a configured Microsoft Store `PRODUCT_ID`.
- Prefers bundle packages, then falls back to x64 or neutral app packages.
- Skips duplicate work with a secret-backed memory marker.
- Archives new packages to private GitHub Releases.
- Can be triggered manually or from an external scheduler such as `cron-job.org`.
- Keeps optional mirror integrations in the workflow, disabled by default.

## How It Works

The workflow lives at `.github/workflows/auto-udrop-updater.yml`.

1. Read the last processed build from `NIX_LAST_VERSION`.
2. Query DanStore for package metadata.
3. Select the best downloadable package candidate.
4. Compare the selected package against the stored marker.
5. Download only when the package is new.
6. Create or update a GitHub Release for the package version.
7. Upload the package as a release asset.
8. Update `NIX_LAST_VERSION` so the next run is idempotent.

The workflow is locked with GitHub Actions concurrency, so repeated triggers on the same branch do not race each other.

## Quick Start

1. Click **Use this template** on GitHub.
2. Create the generated repository as **private**.
3. Add the required repository secrets.
4. Run **Nix - Official Mirror** from the Actions tab.
5. Confirm the generated GitHub Release contains the package asset.

Using a template is preferred over forking because the archive repository starts private, independent, and free of template history.

## Required Secrets

Add these under **Settings -> Secrets and variables -> Actions**.

| Secret | Required | Purpose |
| --- | --- | --- |
| `PRODUCT_ID` | Yes | Microsoft Store product ID to archive. |
| `GH_PAT` | Yes | Fine-grained token used to update `NIX_LAST_VERSION` and trigger the workflow externally. |
| `NIX_LAST_VERSION` | Recommended | Last processed marker. Set to `none` for the first run. |

Recommended `GH_PAT` permissions:

- Repository access: this generated archive repo only
- `Actions: Write`
- `Secrets: Write`

## Optional Mirror Secrets

The workflow still contains mirror support, but all mirror flags are disabled by default:

```yaml
UDROP_ENABLED: 'false'
TERABOX_ENABLED: 'false'
MEGA_ENABLED: 'false'
DDOWNLOAD_ENABLED: 'false'
```

Only add these secrets if you intentionally re-enable the related mirror steps.

| Service | Secrets |
| --- | --- |
| uDrop | `UDROP_KEY1`, `UDROP_KEY2`, `UDROP_FOLDER_ID` |
| MEGA | `MEGA_EMAIL`, `MEGA_PASSWORD`, `MEGA_REMOTE_DIR` |
| TeraBox | `TERABOX_NDUS`, `TERABOX_JSTOKEN`, `TERABOX_APP_ID`, `TERABOX_BROWSER_ID`, `TERABOX_REMOTE_DIR`, `TERABOX_BDSTOKEN` |
| DDownload | `DDOWNLOAD_API_KEY` |

> [!NOTE]
> TeraBox support uses an unofficial reverse-engineered client and may break if TeraBox changes its web API.

## Package Selection

Candidate priority:

1. `MSIXBUNDLE`, `APPXBUNDLE`, `EMSIXBUNDLE`
2. `MSIX`, `APPX`

Allowed architectures:

- `neutral`
- `x64`

When versions are parseable, the workflow sorts by highest semantic version first.

## Triggering From cron-job.org

GitHub's native schedule can drift, so `cron-job.org` is useful for exact timed runs.

Request:

```http
POST https://api.github.com/repos/OWNER/REPO/actions/workflows/auto-udrop-updater.yml/dispatches
```

Headers:

```http
Authorization: Bearer YOUR_GH_PAT
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
Content-Type: application/json
```

Body:

```json
{"ref":"main"}
```

Expected response:

```text
204 No Content
```

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `PRODUCT_ID secret is empty` | Add `PRODUCT_ID` in repository Actions secrets. |
| DanStore returns empty, 403, or times out | Retry later. The workflow already retries with browser-like headers and backoff. |
| The same package uploads again | Check `NIX_LAST_VERSION`, release assets, and whether the workflow is running from the latest YAML. |
| Memory secret does not update | Confirm `GH_PAT` exists and has `Secrets: Write` permission for the repo. |
| cron-job.org returns 401 or 403 | Rotate/check the token and confirm `Actions: Write` permission. |
| cron-job.org returns 404 | Confirm the owner, repo, branch, and workflow filename in the dispatch URL. |

## Repository Layout

```text
.github/
  scripts/
    terabox-sync.cjs
    test-udrop.mjs
    test-udrop.ps1
  workflows/
    auto-udrop-updater.yml
danstore_bundle.js
danstore_bundle.js.map
userinput.py
```

## Security Notes

- Do not commit package credentials, API keys, cookies, or download tokens.
- Keep generated archive repositories private.
- Store sync state in GitHub Secrets, not in files.
- Use fine-grained tokens scoped to one archive repo.
- Review third-party mirror steps before enabling them.

## Contributors

<a href="https://github.com/FahadBinHussain/nix/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=FahadBinHussain/nix" alt="Contributors" />
</a>
