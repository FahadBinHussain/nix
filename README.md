# Nix - Private App Archive Template

Template repository for creating a private Microsoft Store app archive.

Use this repo as a template, create your generated repository as **private**, and let GitHub Actions save each detected app version as a private GitHub Release asset.

This project is designed for personal archival. It does not grant permission to redistribute proprietary apps, installers, packages, or binaries. If you make your generated repository public or publish archived files elsewhere, you are responsible for that choice.

## Template Usage

Recommended setup:

1. Click **Use this template** on GitHub.
2. Create a new repository from the template.
3. Set the new repository visibility to **Private**.
4. Add the required secrets listed below.
5. Run the workflow manually or trigger it from `cron-job.org`.

Why use a template instead of a fork:

- A generated repository can be private from the start.
- GitHub shows `generated from <template-owner>/<template-repo>` on the generated repo.
- The generated repo starts as its own archive, without carrying the template's full git history.

## What This Project Does

Production-ready GitHub Actions pipeline that:
- resolves the latest Microsoft Store package for a target `PRODUCT_ID` via DanStore API,
- prevents duplicate processing using a private memory marker,
- archives new builds to private GitHub Releases,
- keeps optional third-party mirror code in the repo behind disabled flags,
- stores sync state in private GitHub Secrets.

This repository runs an automated sync workflow for one Microsoft Store app:

1. Query latest package metadata from `danstore-ms.vercel.app`.
2. Select the best package candidate (bundle preferred, x64/neutral fallback).
3. Check if this build was already processed (secret-based memory marker).
4. Download package only when required.
5. Create or update a private GitHub Release for that version.
6. Upload the package as a release asset.
7. Update private memory marker (`NIX_LAST_VERSION`) to avoid reprocessing.

## Workflow Triggers

Workflow file: [auto-udrop-updater.yml](.github/workflows/auto-udrop-updater.yml)

Triggers:
- `workflow_dispatch` (manual)

External schedule:
- `cron-job.org` is recommended for precise timed runs.
- The workflow is triggered remotely through GitHub's `workflow_dispatch` API.

Concurrency:
- One run per branch at a time (`cancel-in-progress: true`) to reduce race conditions.

## Architecture

### Data Sources
- Package metadata: DanStore API
  - `GET /api/packages?id=<PRODUCT_ID>&type=ProductId&environment=Production`
- Primary archive: GitHub Releases
- Optional mirror code kept in workflow, disabled by default:
  - uDrop API v2
  - MEGA via MEGAcmd
  - TeraBox via `terabox-upload-tool`
  - DDownload API

### State Management
- Persistent marker is stored in GitHub Secret: `NIX_LAST_VERSION`
- Marker format:
  - `version|filename` (preferred)
  - Backward-compatible with single-value legacy markers.

### Idempotency Strategy
- Layer 1: Compare candidate against `NIX_LAST_VERSION`.
- Layer 2: Use a release tag derived from version or filename.
- Layer 3: Concurrency lock for overlapping runs.

This combination is what makes repeated runs safe.

## Required Secrets

Configure these in:
`Settings -> Secrets and variables -> Actions`

Required:
- `PRODUCT_ID`: Microsoft Store Product ID (example: `9WZDNCRFJ3TJ`)
- `GH_PAT`: GitHub token used for both:
  - updating `NIX_LAST_VERSION`
  - external `workflow_dispatch` calls from `cron-job.org`

Optional (recommended):
- `NIX_LAST_VERSION`: Initial sync marker (set `none` for first run).

Optional if you later re-enable third-party mirrors:
- `UDROP_KEY1`: uDrop API key 1
- `UDROP_KEY2`: uDrop API key 2
- `UDROP_FOLDER_ID`: Target uDrop folder ID. If omitted, root folder is used.
- `MEGA_EMAIL`: MEGA account email
- `MEGA_PASSWORD`: MEGA account password
- `MEGA_REMOTE_DIR`: Target folder in MEGA. If omitted, upload goes to `/`.
- `TERABOX_NDUS`: TeraBox `ndus` cookie value from your logged-in browser session.
- `TERABOX_JSTOKEN`: TeraBox `jsToken` value from browser network requests.
- `TERABOX_APP_ID`: Usually `250528`. Set it explicitly if your session uses a different value.
- `TERABOX_BROWSER_ID`: Optional TeraBox `browserid` cookie value from your logged-in browser session.
- `TERABOX_REMOTE_DIR`: Target folder in TeraBox. If omitted, upload goes to `/nix`.
- `TERABOX_BDSTOKEN`: Optional TeraBox token if your session requires it.
- `DDOWNLOAD_API_KEY`: DDownload API key.

## Required Token Permissions

`GH_PAT` must allow both secret updates and remote workflow dispatch for this repository.

Recommended fine-grained PAT scope:
- Repository access: this repo only
- Permissions:
  - `Actions: Write`
  - `Secrets: Write`

If you use the same PAT in both GitHub Actions and `cron-job.org`, these combined permissions cover both use cases.

## Package Selection Logic

Priority order:
1. `MSIXBUNDLE` / `APPXBUNDLE` / `EMSIXBUNDLE`
2. `MSIX` / `APPX`

Architecture filter:
- `neutral`
- `x64`

Version sorting:
- Highest semantic version first (when parseable).

## Operational Notes

- This workflow intentionally supports frequent re-runs.
- The primary archive target is private GitHub Releases.
- Third-party mirror code is still present, but `UDROP_ENABLED`, `MEGA_ENABLED`, `DDOWNLOAD_ENABLED`, and `TERABOX_ENABLED` are disabled by default.
- If you later re-enable uDrop, MEGA, or DDownload, those steps still contain their destination-side existence checks.
- The TeraBox integration uses an unofficial reverse-engineered client and may break if TeraBox changes its web API.
- State is private (secret-based), not committed to a branch.
- External scheduling via `cron-job.org` is preferred for better timing precision than GitHub's native scheduler.

## How To Use

1. Generate a private repository from this template.
2. Add required secrets.
3. Configure `cron-job.org` or trigger manually.
4. Check Actions logs for:
   - package resolution
   - dedupe decision
   - upload status
   - memory marker update

## cron-job.org Setup

Use `cron-job.org` to trigger the workflow on an exact schedule.

Request configuration:
- URL:
  `https://api.github.com/repos/OWNER/REPO/actions/workflows/auto-udrop-updater.yml/dispatches`
- Method:
  `POST`
- Content-Type:
  `application/json`
- Request body:

```json
{"ref":"main"}
```

Headers:
- `Authorization: Bearer YOUR_GH_PAT`
- `Accept: application/vnd.github+json`
- `X-GitHub-Api-Version: 2022-11-28`

Suggested Bangladesh schedule:
- `06:00`
- `12:00`
- `18:00`
- `00:00`

Expected success response:
- `204 No Content`

Practical note:
- `push` events do not trigger the workflow.
- `cron-job.org` triggers the workflow through `workflow_dispatch`.

## Troubleshooting

### `PRODUCT_ID secret is empty`
- Set `PRODUCT_ID` in repo secrets.

### DanStore API returns empty/403
- Usually transient or anti-bot behavior.
- Retry workflow.
- Ensure request headers in workflow were not removed.

### uDrop auth failed
- Verify `UDROP_KEY1` and `UDROP_KEY2`.
- Check account/API status in uDrop dashboard.

### Duplicate file still appears
- Confirm workflow run used current YAML revision.
- Ensure `UDROP_FOLDER_ID` matches the folder you inspect in uDrop UI.
- Check logs for:
  - `File already exists on uDrop...`
  - `SHOULD_UPDATE_MEMORY=true`

### Memory secret not updating
- Verify `GH_PAT` exists and has permission to set repository secrets.
- Check `Update Memory Secret` step logs.

### cron-job.org trigger fails
- Verify the PAT still has `Actions: Write` and `Secrets: Write`.
- Confirm the request body is exactly `{"ref":"main"}`.
- Confirm the workflow filename in the URL is `auto-udrop-updater.yml`.
- Check for GitHub API response codes such as `401`, `403`, or `404`.

## Security Model

- Secrets are never stored in repository files.
- Sync memory is stored in private GitHub Actions secret.
- GitHub Release uploads use the built-in workflow token with `contents: write`.
- `GH_PAT` is used for updating the memory secret and for external workflow dispatch.
- API credentials are scoped to required services only.
- Keep generated archive repositories private unless you are certain you have permission to publish the archived files.

## Local Repository Contents

- `.github/workflows/auto-udrop-updater.yml` - sync pipeline
- `LICENSE` - MIT license
- `README.md` - project documentation

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
