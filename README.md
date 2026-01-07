# 💎 Prism

A fast, customizable status line for Claude Code.

![New Session](screenshots/new_session.png)

![In Progress](screenshots/in_progress.png)

```
💎 my-app · Opus 4.5 · [████████▒▒] 81% · +658 -210 · $15.14 · main*+ · 𓃰3 · ⚒ · mcp:2
⬢ emulator-5560:6.89 · ⬡ emulator-5562:6.89 ·   iPhone 15:6.89
```

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/himattm/prism/main/install.sh | bash
```

Then restart Claude Code or start a new session.

<details>
<summary>Manual installation</summary>

1. **Download the scripts:**
   ```bash
   curl -o ~/.claude/prism.sh https://raw.githubusercontent.com/himattm/prism/main/prism.sh
   curl -o ~/.claude/prism-idle-hook.sh https://raw.githubusercontent.com/himattm/prism/main/prism-idle-hook.sh
   curl -o ~/.claude/prism-busy-hook.sh https://raw.githubusercontent.com/himattm/prism/main/prism-busy-hook.sh
   chmod +x ~/.claude/prism*.sh
   ```

2. **Enable in Claude Code** (`~/.claude/settings.json`):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "$HOME/.claude/prism.sh"
     },
     "hooks": {
       "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$HOME/.claude/prism-busy-hook.sh"}]}],
       "Stop": [{"hooks": [{"type": "command", "command": "$HOME/.claude/prism-idle-hook.sh"}]}]
     }
   }
   ```

3. **Restart Claude Code** or start a new session.

</details>

## Let Claude Set It Up

Copy one of these prompts into Claude Code:

**Full installation:**
```
Install Prism from https://github.com/himattm/prism - run the install script and configure a .prism.json for this repo with an icon of my choice.
```

**Per-repo setup only:**
```
Create a .prism.json for this repo. Suggest some icon options for me to choose from, then configure my Android package name and iOS bundle ID.
```

## Configuration

Prism uses a 3-tier config system. Higher tiers override lower tiers:

```
.prism.local.json              ← Your personal overrides (gitignored)
       ↓ overrides
.prism.json                    ← Repo config (commit for your team)
       ↓ overrides
~/.claude/prism-config.json    ← Your global defaults
```

### Quick Setup

```bash
# Create global defaults (all your repos)
~/.claude/prism.sh init-global

# Create repo config (for this project)
~/.claude/prism.sh init
```

Or copy from [examples/](examples/).

### When to Use Each Tier

| Tier | File | Commit? | Use for |
|------|------|---------|---------|
| **Global** | `~/.claude/prism-config.json` | No | Your default sections, personal preferences |
| **Repo** | `.prism.json` | Yes | Team icon, package names, shared settings |
| **Local** | `.prism.local.json` | No | Personal icon override, machine-specific tweaks |

### Global Config

Your defaults across all repos. Create with `prism.sh init-global`:

```json
{
  "sections": ["dir", "model", "context", "cost", "git"]
}
```

### Repo Config

Shared team settings. Create with `prism.sh init`:

```json
{
  "icon": "🤖",
  "android": {
    "packages": ["com.myapp.debug", "com.myapp"]
  },
  "ios": {
    "bundleIds": ["com.myapp.debug"]
  }
}
```

### Local Overrides

Personal tweaks not committed to git. Add `.prism.local.json` to your `.gitignore`:

```json
{
  "icon": "🔧"
}
```

### Sections

Control what appears and in what order:

```json
{
  "sections": ["dir", "model", "context", "cost", "git", "gradle", "mcp", "devices"]
}
```

Available: `dir`, `model`, `context`, `linesChanged`, `cost`, `git`, `gradle`, `xcode`, `mcp`, `devices`

### Full Example Config

A complete `.prism.json` with all available options:

```json
{
  "icon": "🤖",
  "sections": [
    ["dir", "model", "context", "linesChanged", "cost", "git", "gradle", "xcode", "mcp"],
    ["devices"]
  ],
  "android": {
    "packages": ["com.myapp.debug", "com.myapp", "com.myapp.*"]
  },
  "ios": {
    "bundleIds": ["com.myapp.debug", "com.myapp.*"]
  }
}
```

| Field | Description |
|-------|-------------|
| `icon` | Emoji prefix for directory display |
| `sections` | Array of sections (single line) or array of arrays (multi-line) |
| `android.packages` | Package names to check for version display (supports `*` glob) |
| `ios.bundleIds` | Bundle IDs to check for version display (supports `*` glob) |

**Single-line format:** `"sections": ["dir", "model", "context", ...]`

**Multi-line format:** `"sections": [["line1", "sections"], ["line2", "sections"], ...]`

## Features

| Feature | Description |
|---------|-------------|
| **Smart Directory** | Shows project root at start, abbreviates when in subdirs: `cms/screenshots` |
| **Context Bar** | Visual `[████░░▒▒]` showing usage, free space, and auto-compact buffer zone |
| **Code Stats** | Uncommitted lines changed via git diff (`+658 -210`) and session cost (`$15.14`) |
| **Git** | Branch with dirty indicators (`*` staged, `**` unstaged, `+` untracked) |
| **Android** | Device list with app versions, `⬢` targeted / `⬡` non-targeted |
| **iOS** | Simulator list with app versions,  Apple logo icon |
| **Gradle** | `𓃰3` daemons running, `𓃰?` cold start expected |
| **Xcode** | `⚒2` builds running |
| **MCP** | `mcp:2` servers configured |

### Directory Display

The directory section shows where Claude was started, with smart handling when you navigate to subdirectories:

| Location | Display |
|----------|---------|
| Project root | `claude-mobiledev-statusline` (full name, cyan) |
| In subdirectory | `cms/screenshots` (abbreviated root dim, subdir bright) |
| Deep nesting | `cms/k/v/engine` (last 3 dirs, intermediate ones abbreviated) |

**Abbreviation rules:**
- Project name > 6 chars with hyphens: first letter of each segment (`claude-mobiledev-statusline` → `cms`)
- Project name > 6 chars without hyphens: first 3 characters (`screenshots` → `scr`)
- Deep paths: show last 3 directories, abbreviate all but the final one to first letter

## Reference

### Symbols

| Symbol | Meaning |
|--------|---------|
| `⬢` | Android device (targeted via ANDROID_SERIAL) |
| `⬡` | Android device (not targeted) |
| `` | iOS simulator (Apple logo) |
| `𓃰` | Gradle daemon |
| `⚒` | Xcode build |
| `█░▒` | Context: used, free, buffer |

### Troubleshooting

**Version shows "--"**
- Wait ~2 seconds for cache population
- Verify app is installed: `adb shell pm list packages | grep yourapp`

**Config changes not showing**
- Config is cached per-session. Start new session or: `rm /tmp/prism-config-*`

**Git info seems stale**
- Git branch/status and diff stats are cached for 2 seconds to avoid blocking other git operations

**Context % doesn't match /context**
- Adjust `SYSTEM_OVERHEAD_TOKENS` in script (default: 23000)

## Dependencies

- `jq` - JSON parsing
- `adb` - Android device detection (optional)
- `xcrun simctl` - iOS simulator detection (macOS only, optional)

## Development

```bash
# Run tests
./test.sh

# Test CLI commands
./prism.sh help
./prism.sh init
./prism.sh init-global
```

## License

MIT
