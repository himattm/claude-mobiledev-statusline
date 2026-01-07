# Gradle Plugin

Shows Gradle daemon status for Android/JVM projects.

## Icon

**𓃰** (Egyptian elephant hieroglyph - Gradle's logo is an elephant)

## Output Format

| Display | Meaning |
|---------|---------|
| `𓃰3` | 3 Gradle daemons running |
| `𓃰?` | No daemon (cold start expected) |

## When It Shows

Only appears in projects with:
- `build.gradle`
- `build.gradle.kts`
- `settings.gradle`
- `settings.gradle.kts`

Hidden in non-Gradle projects.

## Why It Matters

- Daemons stay running to speed up builds
- `?` means first build will be slower (daemon startup)
- Multiple daemons may exist for different Gradle versions

## Installation

```bash
cp prism-plugin-gradle.sh ~/.claude/prism-plugins/
```

## Testing

```bash
./test.sh
```
