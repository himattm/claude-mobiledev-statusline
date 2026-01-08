# Prism

A fast, customizable status line for Claude Code.

![Example](screenshots/example.png)

## Features

- **Fast** - Native Go with parallel plugin execution
- **Actionable context bar** - Shows % until autocompact triggers
- **Rich git info** - Branch, dirty status, upstream tracking (⇣⇡)
- **Mobile dev ready** - Android/iOS devices, Gradle/Xcode build status
- **Extensible** - Write custom plugins in any language

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/himattm/prism/main/install.sh | bash
```

Restart Claude Code or start a new session.

<details>
<summary>Manual installation</summary>

```bash
# Download pre-built binary (macOS/Linux)
curl -fsSL https://github.com/himattm/prism/releases/latest/download/prism-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') -o ~/.claude/prism
chmod +x ~/.claude/prism

# Or build from source
git clone https://github.com/himattm/prism.git
cd prism && go build -o ~/.claude/prism ./cmd/prism/
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "$HOME/.claude/prism"
  },
  "hooks": {
    "UserPromptSubmit": [{"hooks": [
      {"type": "command", "command": "$HOME/.claude/prism-busy-hook.sh"},
      {"type": "command", "command": "$HOME/.claude/prism-update-hook.sh"}
    ]}],
    "Stop": [{"hooks": [
      {"type": "command", "command": "$HOME/.claude/prism-idle-hook.sh"}
    ]}]
  }
}
```

</details>

## Configuration

Prism uses a 3-tier config system (highest priority first):

| File | Purpose |
|------|---------|
| `.claude/prism.local.json` | Personal overrides (gitignored) |
| `.claude/prism.json` | Repo config (commit for your team) |
| `~/.claude/prism-config.json` | Global defaults |

### Quick Setup

```bash
~/.claude/prism init-global  # Create global defaults
~/.claude/prism init         # Create repo config
```

### Example Config

```json
{
  "icon": "🚀",
  "sections": ["dir", "model", "context", "cost", "git", "devices"],
  "autocompactBuffer": 22.5
}
```

### Multi-line Layout

```json
{
  "sections": [
    ["dir", "model", "context", "cost", "git"],
    ["devices"]
  ]
}
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `icon` | string | `"💎"` | Icon before project name |
| `sections` | array | See below | Sections to display |
| `autocompactBuffer` | number | `22.5` | Autocompact buffer % (0 if disabled) |
| `plugins` | object | `{}` | Plugin-specific config |

## Sections

### Built-in

| Section | Description | Example |
|---------|-------------|---------|
| `dir` | Project name + subdirectory | `💎 prism/internal` |
| `model` | Current model | `Opus 4.5` |
| `context` | Context usage bar | `[████░░░░▒▒] 56%` |
| `linesChanged` | Uncommitted changes | `+123 -45` |
| `cost` | Session cost | `$1.23` |

### Context Bar

Shows **actionable** usage - percentage of capacity before autocompact triggers:

```
[█████░░░▒▒] 56%
 ^^^^^ ^^^ ^^
 used  free buffer
```

- **100% = autocompact will trigger**
- Colors: white (<70%), yellow (70-89%), red (90%+)
- Buffer `▒▒` only shows when autocompact is enabled
- Set `"autocompactBuffer": 0` if you disabled autocompact

### Plugins

| Plugin | Description | Example |
|--------|-------------|---------|
| `git` | Branch, dirty, upstream | `main*+2 ⇣3⇡1` |
| `devices` | Android/iOS devices | `⬡ Pixel · ⬡ iPhone` |
| `gradle` | Gradle daemon count | `gradle:3` |
| `xcode` | Xcode build status | `xcode:building` |
| `mcp` | MCP server count | `mcp:2` |
| `update` | Update indicator | `⬆` |

## Writing Plugins

Plugins are scripts that receive JSON on stdin and output formatted text.

### Interface

```
INPUT:  JSON on stdin (context, config, colors)
OUTPUT: Formatted text on stdout
EXIT:   0 = show, 0 + empty = hide, non-zero = error
```

### Input JSON

```json
{
  "prism": {
    "version": "0.2.0",
    "project_dir": "/path/to/project",
    "current_dir": "/path/to/project/subdir",
    "session_id": "abc123",
    "is_idle": true
  },
  "session": {
    "model": "Opus 4.5",
    "context_pct": 45,
    "cost_usd": 1.23,
    "lines_added": 100,
    "lines_removed": 50
  },
  "config": {
    "your_plugin": { "option": "value" }
  },
  "colors": {
    "red": "\u001b[31m",
    "green": "\u001b[32m",
    "yellow": "\u001b[33m",
    "blue": "\u001b[34m",
    "magenta": "\u001b[35m",
    "cyan": "\u001b[36m",
    "gray": "\u001b[90m",
    "dim": "\u001b[2m",
    "reset": "\u001b[0m"
  }
}
```

### Example: Weather Plugin

```bash
#!/bin/bash
# ~/.claude/prism-plugins/prism-plugin-weather.sh

INPUT=$(cat)

# Parse config
LOCATION=$(echo "$INPUT" | jq -r '.config.weather.location // "New York"')

# Get colors
CYAN=$(echo "$INPUT" | jq -r '.colors.cyan')
RESET=$(echo "$INPUT" | jq -r '.colors.reset')

# Only fetch when idle
IS_IDLE=$(echo "$INPUT" | jq -r '.prism.is_idle')
[ "$IS_IDLE" != "true" ] && exit 0

# Fetch and display
TEMP=$(curl -sf "wttr.in/${LOCATION}?format=%t" 2>/dev/null) || exit 0
echo -e "${CYAN}${TEMP}${RESET}"
```

Config:

```json
{
  "sections": ["dir", "model", "context", "weather", "git"],
  "plugins": {
    "weather": { "location": "San Francisco" }
  }
}
```

### Best Practices

1. **Cache expensive operations** - Use `/tmp/prism-{plugin}-*` with TTL
2. **Check `is_idle`** - Only run slow ops when Claude is waiting
3. **Use provided colors** - Consistent with user's terminal
4. **Exit cleanly** - Empty output hides section
5. **Keep it fast** - Target <100ms

### Installing Plugins

```bash
cp my-plugin.sh ~/.claude/prism-plugins/prism-plugin-myplugin.sh
chmod +x ~/.claude/prism-plugins/prism-plugin-myplugin.sh

# Then add "myplugin" to sections in config
```

## Development

```bash
go build -o prism-go ./cmd/prism/
go test ./...
```

## License

MIT
