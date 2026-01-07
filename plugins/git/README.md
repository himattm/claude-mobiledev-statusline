# Git Plugin

Shows the current git branch and working tree status.

## Output Format

```
branch_name[status_indicators]
```

## Status Indicators

| Indicator | Meaning |
|-----------|---------|
| `*` | Staged changes (ready to commit) |
| `**` | Staged + unstaged changes |
| `+` | Untracked files |
| `⇣` | Behind upstream (commits to pull) |
| `⇡` | Ahead of upstream (commits to push) |

## Examples

| Output | Description |
|--------|-------------|
| `main` | Clean working tree |
| `main*` | Staged changes only |
| `main**` | Staged and unstaged changes |
| `main+` | Untracked files only |
| `main**+` | All three: staged, unstaged, untracked |
| `main⇣` | Behind upstream, need to pull |
| `main⇡` | Ahead of upstream, need to push |
| `main⇣⇡` | Diverged from upstream |
| `main**+⇣⇡` | All indicators |
| `abc123` | Detached HEAD (short commit hash) |

## Behavior

- **Idle-only refresh**: Only updates when session is idle
- **2-second cache**: Avoids repeated git calls
- **Auto-detection**: Hidden in non-git directories
- **1-second timeout**: Prevents hangs on slow repos

## Installation

```bash
cp prism-plugin-git.sh ~/.claude/prism-plugins/
```

## Testing

```bash
./test.sh
```
