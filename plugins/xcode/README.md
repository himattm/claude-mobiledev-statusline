# Xcode Plugin

Shows Xcode build status for iOS/macOS projects.

## Icon

**⚒** (crossed hammers - represents building)

## Output Format

| Output | Meaning |
|--------|---------|
| `⚒` | Xcode project, no builds running |
| `⚒2` | 2 xcodebuild processes running |

## When It Shows

Only appears in projects with:
- `*.xcodeproj`
- `*.xcworkspace`

Hidden in non-Xcode projects.

## Why It Matters

- Shows when builds are in progress
- Multiple builds may run (simulator + device)
- Helps know when you're waiting on a build

## Installation

```bash
cp prism-plugin-xcode.sh ~/.claude/prism-plugins/
```

## Testing

```bash
./test.sh
```
