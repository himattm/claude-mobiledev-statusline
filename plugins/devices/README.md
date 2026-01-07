# Devices Plugin

Shows connected Android devices and iOS simulators with optional app versions.

## Icons

| Icon | Description |
|------|-------------|
| `⬢` | Android device (active) - targeted by `ANDROID_SERIAL` or only device |
| `⬡` | Android device (inactive) - not targeted when multiple connected |
| `` | iOS simulator (Apple logo U+F8FF) |

## Output Examples

| Output | Description |
|--------|-------------|
| `⬢ emulator-5554` | Single Android device |
| `⬢ emulator-5554:1.2.3` | Android with app version |
| `⬡ emu-5554 · ⬢ emu-5556` | Multiple devices, second targeted |
| ` iPhone 15 Pro` | iOS simulator |
| ` iPhone 15:2.0.0` | iOS simulator with app version |

## Configuration

```json
{
  "plugins": {
    "devices": {
      "android": {
        "packages": ["com.myapp.debug", "com.myapp.*"]
      },
      "ios": {
        "bundleIds": ["com.myapp.debug", "com.company.*"]
      }
    }
  }
}
```

## Notes

- **Glob patterns**: Use `*` wildcards (`com.myapp.*`)
- **Version display**: Only shown if packages/bundleIds configured
- **Not found**: Shows `--` if configured package not installed
- **30-second cache**: Version lookups are cached
- **ANDROID_SERIAL**: Controls which device shows as active

## Installation

```bash
cp prism-plugin-devices.sh ~/.claude/prism-plugins/
```

## Testing

```bash
./test.sh
```
