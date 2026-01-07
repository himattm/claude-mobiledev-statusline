# Update Plugin

Shows an indicator when a newer version of Prism is available.

## Output

- `⬆` (cyan) - Update available
- Empty - No update available or check disabled

## Configuration

```json
{
  "plugins": {
    "update": {
      "enabled": true,
      "check_interval_hours": 24
    }
  }
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable the update check |
| `check_interval_hours` | number | `24` | How often to check for updates (in hours) |

## How It Works

1. Checks cache at `/tmp/prism-update-check` for recent results
2. If cache is stale (older than `check_interval_hours`) AND session is idle:
   - Fetches the latest `prism.sh` from GitHub
   - Extracts the VERSION variable
   - Compares with local version using semver
3. Displays `⬆` if remote version is newer

## Updating

When you see the update indicator, run:

```bash
prism update
```

This will prompt you to confirm, then download and install the latest version.

## Cache

- Location: `/tmp/prism-update-check`
- Format: JSON with `checked_at`, `local_version`, `remote_version`, `update_available`
- Default TTL: 24 hours

## Network Behavior

- Only checks when session is idle (won't slow down active work)
- 3-second timeout on network requests
- Gracefully handles network failures (uses cached result)
