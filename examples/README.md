# Prism Config Examples

Copy and customize these templates for your setup.

## Config Precedence (highest to lowest)

```
.prism.local.json          # Your personal overrides (gitignored)
       ↓
.prism.json                # Repo config (commit for your team)
       ↓
~/.claude/prism-config.json   # Your global defaults
```

## Files

| File | Copy to | Purpose |
|------|---------|---------|
| `global-config.json` | `~/.claude/prism-config.json` | Your default settings across all repos |
| `repo-config.json` | `.prism.json` | Team settings for a specific repo |
| `local-config.json` | `.prism.local.json` | Your personal overrides (add to .gitignore) |

## Quick Setup

```bash
# Global defaults (all repos)
cp examples/global-config.json ~/.claude/prism-config.json

# Repo config (commit this)
cp examples/repo-config.json .prism.json

# Personal overrides (gitignore this)
cp examples/local-config.json .prism.local.json
echo '.prism.local.json' >> .gitignore
```
