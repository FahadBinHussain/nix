# Nix - Microsoft Store Mirror to uDrop and MEGA

Production-ready GitHub Actions pipeline that:
- resolves the latest Microsoft Store package for a target `PRODUCT_ID` via DanStore API,
- prevents duplicate uploads using both state markers and destination-side checks,
- uploads new builds to uDrop,
- uploads new builds to MEGA,
- stores sync state in private GitHub Secrets (not public branches).

## What This Project Does

This repository runs an automated sync workflow for one Microsoft Store app:

1. Query latest package metadata from `danstore-ms.vercel.app`.
2. Select the best package candidate (bundle preferred, x64/neutral fallback).
3. Check if this build was already processed (secret-based memory marker).
4. Check if the exact filename already exists in uDrop (idempotency guard).
5. Download package only when required.
6. Upload to uDrop.
7. Upload to MEGA.
8. Update private memory marker (`NIX_LAST_VERSION`) to avoid reprocessing.

## Workflow Triggers

Workflow file: [auto-udrop-updater.yml](/C:/Users/Admin/Downloads/nix/.github/workflows/auto-udrop-updater.yml)

Triggers:
- `push`
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
- Destination: uDrop API v2
  - `/authorize`
  - `/folder/listing`
  - `/file/upload`
- Destination: MEGA via MEGAcmd
  - official Windows installer
  - `mega-login`
  - `mega-mkdir`
  - `mega-put`
  - `mega-logout`

### State Management
- Persistent marker is stored in GitHub Secret: `NIX_LAST_VERSION`
- Marker format:
  - `version|filename` (preferred)
  - Backward-compatible with single-value legacy markers.

### Idempotency Strategy
- Layer 1: Compare candidate against `NIX_LAST_VERSION`.
- Layer 2: Query uDrop folder listing and skip if same filename already exists.
- Layer 3: Concurrency lock for overlapping runs.

This combination is what makes repeated runs safe.

## Required Secrets

Configure these in:
`Settings -> Secrets and variables -> Actions`

Required:
- `PRODUCT_ID`: Microsoft Store Product ID (example: `9WZDNCRFJ3TJ`)
- `UDROP_KEY1`: uDrop API key 1
- `UDROP_KEY2`: uDrop API key 2
- `MEGA_EMAIL`: MEGA account email
- `MEGA_PASSWORD`: MEGA account password
- `GH_PAT`: GitHub token used for both:
  - updating `NIX_LAST_VERSION`
  - external `workflow_dispatch` calls from `cron-job.org`

Optional (recommended):
- `UDROP_FOLDER_ID`: Target uDrop folder ID. If omitted, root folder is used.
- `MEGA_REMOTE_DIR`: Target folder in MEGA. If omitted, upload goes to `/`.
- `NIX_LAST_VERSION`: Initial sync marker (set `none` for first run).

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
- If the same build already exists in uDrop, it should skip upload and finish quickly.
- On upload runs, the workflow mirrors to uDrop first and then to MEGA.
- State is private (secret-based), not committed to a branch.
- External scheduling via `cron-job.org` is preferred for better timing precision than GitHub's native scheduler.

## How To Use

1. Add required secrets.
2. Configure `cron-job.org` or trigger manually.
3. Check Actions logs for:
   - package resolution
   - dedupe decision
   - upload status
   - memory marker update

## cron-job.org Setup

Use `cron-job.org` to trigger the workflow on an exact schedule.

Request configuration:
- URL:
  `https://api.github.com/repos/fahadbinhussain/nix/actions/workflows/auto-udrop-updater.yml/dispatches`
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
- `push` events still trigger the workflow independently.
- `cron-job.org` only replaces the old GitHub `schedule` trigger.

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
- Workflow uses `contents: read` permission by default.
- API credentials are scoped to required services only.

## Local Repository Contents

- `.github/workflows/auto-udrop-updater.yml` - sync pipeline
- `LICENSE` - MIT license
- `README.md` - project documentation

## License

This project is licensed under the MIT License. See [LICENSE](/C:/Users/Admin/Downloads/nix/LICENSE).
