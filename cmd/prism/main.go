package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/himattm/prism/internal/config"
	"github.com/himattm/prism/internal/plugin"
	"github.com/himattm/prism/internal/statusline"
)

const Version = "0.2.0"

func main() {
	if len(os.Args) < 2 {
		// No args = status line mode (read JSON from stdin)
		runStatusLine()
		return
	}

	// CLI mode
	switch os.Args[1] {
	case "version", "--version", "-v":
		fmt.Printf("Prism %s (Go)\n", Version)

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
`, Version)
}

func handlePluginCommand(args []string) {
	if len(args) == 0 {
		args = []string{"list"}
	}

	pm := plugin.NewManager()

	switch args[0] {
	case "list", "ls":
		pm.List()

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
	fmt.Println("Checking for Prism updates...")
	// TODO: Implement update logic
	fmt.Println("Update functionality coming soon")
}

func handleCheckUpdate() {
	fmt.Println("Checking for Prism updates...")
	// TODO: Implement check-update logic
	fmt.Printf("Local version:  %s\n", Version)
	fmt.Println("Check-update functionality coming soon")
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
