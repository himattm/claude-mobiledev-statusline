package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/himattm/prism/internal/config"
	"github.com/himattm/prism/internal/hooks"
	"github.com/himattm/prism/internal/plugin"
	"github.com/himattm/prism/internal/plugins"
	"github.com/himattm/prism/internal/statusline"
	"github.com/himattm/prism/internal/update"
	"github.com/himattm/prism/internal/version"
)

func main() {
	if len(os.Args) < 2 {
		// No args = status line mode (read JSON from stdin)
		runStatusLine()
		return
	}

	// CLI mode
	switch os.Args[1] {
	case "version", "--version", "-v":
		fmt.Printf("Prism %s (Go)\n", version.Version)

	case "help", "--help", "-h":
		printHelp()

	case "plugin", "plugins":
		handlePluginCommand(os.Args[2:])

	case "update":
		handleUpdate()

	case "check-update":
		handleCheckUpdate()

	case "init":
		handleInit()

	case "init-global":
		handleInitGlobal()

	case "hook":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "Usage: prism hook <idle|busy>")
			os.Exit(1)
		}
		handleHook(os.Args[2])

	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		fmt.Fprintln(os.Stderr, "Run 'prism help' for usage")
		os.Exit(1)
	}
}

func runStatusLine() {
	// Read JSON input from stdin
	var input statusline.Input
	decoder := json.NewDecoder(os.Stdin)
	if err := decoder.Decode(&input); err != nil {
		fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
		os.Exit(1)
	}

	// Load config
	cfg := config.Load(input.Workspace.ProjectDir)

	// Build and render status line
	sl := statusline.New(input, cfg)
	output := sl.Render()

	fmt.Print(output)
}

func printHelp() {
	fmt.Printf(`Prism %s - A fast, customizable status line for Claude Code

Usage:
  prism init                  Create .claude/prism.json in current directory
  prism init-global           Create ~/.claude/prism-config.json
  prism update                Check for Prism updates and install
  prism check-update          Check for Prism updates (no install)
  prism version               Show version
  prism help                  Show this help

Plugin commands:
  prism plugin list           List installed plugins with versions
  prism plugin add <url>      Install plugin from GitHub/URL
  prism plugin check-updates  Check plugins for updates
  prism plugin update <name>  Update a plugin (or --all)
  prism plugin remove <name>  Remove a plugin

Config precedence (highest to lowest):
  1. .claude/prism.local.json    Your personal overrides (gitignored)
  2. .claude/prism.json          Repo config (commit for your team)
  3. ~/.claude/prism-config.json Global defaults
`, version.Version)
}

func handlePluginCommand(args []string) {
	if len(args) == 0 {
		args = []string{"list"}
	}

	pm := plugin.NewManager()

	switch args[0] {
	case "list", "ls":
		// Get native plugins from registry
		registry := plugins.NewRegistry()
		nativeNames := registry.List()
		nativePlugins := make([]plugin.NativePluginInfo, len(nativeNames))
		for i, name := range nativeNames {
			nativePlugins[i] = plugin.NativePluginInfo{
				Name:    name,
				Version: version.Version,
			}
		}
		pm.List(nativePlugins)

	case "add", "install":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Usage: prism plugin add <url>")
			os.Exit(1)
		}
		if err := pm.Add(args[1]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

	case "check-updates", "check":
		pm.CheckUpdates()

	case "update", "upgrade":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Usage: prism plugin update <name|--all>")
			os.Exit(1)
		}
		if err := pm.Update(args[1]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

	case "remove", "uninstall", "rm":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Usage: prism plugin remove <name>")
			os.Exit(1)
		}
		if err := pm.Remove(args[1]); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

	default:
		fmt.Printf("Unknown plugin command: %s\n", args[0])
		fmt.Println("Run 'prism plugin' for usage")
		os.Exit(1)
	}
}

func handleUpdate() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	fmt.Println("Checking for updates...")

	info, err := update.Check(ctx)
	if err != nil {
		fmt.Printf("Current version: %s\n", version.Version)
		fmt.Fprintf(os.Stderr, "\nCannot update: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Current version: %s\n", info.CurrentVersion)
	fmt.Printf("Latest version:  %s\n", info.LatestVersion)

	if !info.UpdateAvailable {
		fmt.Println("\nYou're already on the latest version!")
		return
	}

	fmt.Println("\nDownloading update...")

	if err := update.Download(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error downloading update: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("\nUpdated to %s!\n", info.LatestVersion)
}

func handleCheckUpdate() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	fmt.Println("Checking for updates...")

	info, err := update.Check(ctx)
	if err != nil {
		fmt.Printf("Current version: %s\n", version.Version)
		fmt.Printf("\nCould not check for updates: %v\n", err)
		fmt.Println("You may be running a development build.")
		return
	}

	fmt.Printf("Current version: %s\n", info.CurrentVersion)
	fmt.Printf("Latest version:  %s\n", info.LatestVersion)

	if info.UpdateAvailable {
		fmt.Println("\nUpdate available! Run 'prism update' to install.")
	} else {
		fmt.Println("\nYou're on the latest version.")
	}
}

func handleInit() {
	if err := config.Init("."); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Created .claude/prism.json")
}

func handleInitGlobal() {
	if err := config.InitGlobal(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Created ~/.claude/prism-config.json")
}

func handleHook(hookType string) {
	// Read JSON from stdin (Claude Code provides session info)
	var input hooks.Input
	if err := json.NewDecoder(os.Stdin).Decode(&input); err != nil {
		// Silent fail for hooks - don't break Claude Code
		// Try to continue without session ID
		input = hooks.Input{}
	}

	manager := hooks.NewManager()

	switch hookType {
	case "idle":
		if err := manager.HandleIdle(input); err != nil {
			os.Exit(1)
		}
	case "busy":
		if err := manager.HandleBusy(input); err != nil {
			os.Exit(1)
		}
	case "session-start":
		if err := manager.HandleSessionStart(input); err != nil {
			os.Exit(1)
		}
	case "session-end":
		if err := manager.HandleSessionEnd(input); err != nil {
			os.Exit(1)
		}
	case "pre-compact":
		if err := manager.HandlePreCompact(input); err != nil {
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "Unknown hook type: %s\n", hookType)
		fmt.Fprintln(os.Stderr, "Available hooks: idle, busy, session-start, session-end, pre-compact")
		os.Exit(1)
	}
}
