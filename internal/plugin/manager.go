package plugin

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Manager handles plugin discovery, execution, and management
type Manager struct {
	pluginDir string
}

// NewManager creates a new plugin manager
func NewManager() *Manager {
	homeDir, _ := os.UserHomeDir()
	return &Manager{
		pluginDir: filepath.Join(homeDir, ".claude", "prism-plugins"),
	}
}

// Discover finds all installed plugins
func (m *Manager) Discover() ([]Plugin, error) {
	if err := os.MkdirAll(m.pluginDir, 0755); err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(m.pluginDir)
	if err != nil {
		return nil, err
	}

	var plugins []Plugin
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasPrefix(name, "prism-plugin-") {
			continue
		}

		path := filepath.Join(m.pluginDir, name)
		meta, err := ParseMetadata(path)
		if err != nil {
			// Plugin without proper metadata
			pluginName := strings.TrimPrefix(name, "prism-plugin-")
			pluginName = strings.TrimSuffix(pluginName, filepath.Ext(pluginName))
			meta = Metadata{Name: pluginName}
		}

		plugins = append(plugins, Plugin{
			Name:     meta.Name,
			Path:     path,
			Metadata: meta,
		})
	}

	return plugins, nil
}

// ParseMetadata extracts metadata from plugin header comments
func ParseMetadata(path string) (Metadata, error) {
	file, err := os.Open(path)
	if err != nil {
		return Metadata{}, err
	}
	defer file.Close()

	meta := Metadata{}
	scanner := bufio.NewScanner(file)
	lineCount := 0

	// Regex to match @key value lines
	re := regexp.MustCompile(`^#\s*@(\w+[-\w]*)\s+(.+)$`)

	for scanner.Scan() && lineCount < 20 {
		line := scanner.Text()
		lineCount++

		matches := re.FindStringSubmatch(line)
		if len(matches) == 3 {
			key := strings.ToLower(matches[1])
			value := strings.TrimSpace(matches[2])

			switch key {
			case "name":
				meta.Name = value
			case "version":
				meta.Version = value
			case "description":
				meta.Description = value
			case "author":
				meta.Author = value
			case "source":
				meta.Source = value
			case "update-url":
				meta.UpdateURL = value
			}
		}
	}

	return meta, scanner.Err()
}

// Execute runs a plugin and returns its output
func (m *Manager) Execute(p Plugin, input Input, timeout time.Duration) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, p.Path)

	// Prepare input JSON
	inputJSON, err := json.Marshal(input)
	if err != nil {
		return "", fmt.Errorf("failed to marshal input: %w", err)
	}

	cmd.Stdin = bytes.NewReader(inputJSON)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return "", fmt.Errorf("plugin timed out")
		}
		return "", fmt.Errorf("plugin error: %w (stderr: %s)", err, stderr.String())
	}

	return strings.TrimRight(stdout.String(), "\n"), nil
}

// List prints all installed plugins
func (m *Manager) List() {
	plugins, err := m.Discover()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error discovering plugins: %v\n", err)
		return
	}

	fmt.Println("Installed plugins:")
	fmt.Println()
	fmt.Printf("  %-12s %-10s %-20s %s\n", "NAME", "VERSION", "AUTHOR", "SOURCE")
	fmt.Printf("  %-12s %-10s %-20s %s\n", "----", "-------", "------", "------")

	if len(plugins) == 0 {
		fmt.Println("  (no plugins installed)")
	} else {
		for _, p := range plugins {
			version := p.Metadata.Version
			if version == "" {
				version = "?"
			}
			author := p.Metadata.Author
			if author == "" {
				author = "-"
			}
			source := p.Metadata.Source
			if source == "" {
				source = "-"
			}
			fmt.Printf("  %-12s %-10s %-20s %s\n", p.Name, version, author, source)
		}
	}

	fmt.Println()
	fmt.Printf("Plugin directory: %s\n", m.pluginDir)
}

// Add installs a plugin from a URL
func (m *Manager) Add(url string) error {
	// Normalize URL
	rawURL := url
	if strings.HasPrefix(url, "https://github.com/") && !strings.Contains(url, "/raw/") {
		// Convert GitHub repo URL to raw URL
		parts := strings.Split(strings.TrimPrefix(url, "https://github.com/"), "/")
		if len(parts) >= 2 {
			owner, repo := parts[0], parts[1]
			// Try to guess the plugin file name
			pluginName := strings.TrimPrefix(repo, "prism-plugin-")
			rawURL = fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/main/prism-plugin-%s.sh", owner, repo, pluginName)
		}
	}

	fmt.Printf("Fetching plugin from: %s\n", rawURL)

	// Download plugin
	resp, err := http.Get(rawURL)
	if err != nil {
		return fmt.Errorf("failed to fetch plugin: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to fetch plugin: HTTP %d", resp.StatusCode)
	}

	content, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read plugin: %w", err)
	}

	// Validate it's a prism plugin
	if !bytes.Contains(content, []byte("@prism-plugin")) {
		return fmt.Errorf("file doesn't appear to be a Prism plugin (missing @prism-plugin header)")
	}

	// Write to temp file to parse metadata
	tmpFile, err := os.CreateTemp("", "prism-plugin-*")
	if err != nil {
		return err
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	if _, err := tmpFile.Write(content); err != nil {
		tmpFile.Close()
		return err
	}
	tmpFile.Close()

	// Parse metadata to get plugin name
	meta, err := ParseMetadata(tmpPath)
	if err != nil || meta.Name == "" {
		// Try to extract name from URL
		base := filepath.Base(rawURL)
		meta.Name = strings.TrimPrefix(base, "prism-plugin-")
		meta.Name = strings.TrimSuffix(meta.Name, ".sh")
	}

	// Install plugin
	if err := os.MkdirAll(m.pluginDir, 0755); err != nil {
		return err
	}

	destPath := filepath.Join(m.pluginDir, fmt.Sprintf("prism-plugin-%s.sh", meta.Name))

	// Check if already installed
	if _, err := os.Stat(destPath); err == nil {
		existingMeta, _ := ParseMetadata(destPath)
		fmt.Printf("Plugin '%s' already installed (version %s)\n", meta.Name, existingMeta.Version)
		fmt.Printf("New version: %s\n", meta.Version)
		fmt.Print("Overwrite? [y/N] ")
		var response string
		fmt.Scanln(&response)
		if strings.ToLower(response) != "y" {
			fmt.Println("Cancelled.")
			return nil
		}
	}

	if err := os.WriteFile(destPath, content, 0755); err != nil {
		return fmt.Errorf("failed to write plugin: %w", err)
	}

	fmt.Printf("Installed: %s v%s\n", meta.Name, meta.Version)
	return nil
}

// CheckUpdates checks all plugins for available updates
func (m *Manager) CheckUpdates() {
	plugins, err := m.Discover()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error discovering plugins: %v\n", err)
		return
	}

	fmt.Println("Checking for plugin updates...")
	fmt.Println()

	updatesAvailable := false
	client := &http.Client{Timeout: 5 * time.Second}

	for _, p := range plugins {
		if p.Metadata.UpdateURL == "" {
			fmt.Printf("  %-12s %-10s (no update URL)\n", p.Name, p.Metadata.Version)
			continue
		}

		resp, err := client.Get(p.Metadata.UpdateURL)
		if err != nil {
			fmt.Printf("  %-12s %-10s (fetch failed)\n", p.Name, p.Metadata.Version)
			continue
		}
		defer resp.Body.Close()

		content, _ := io.ReadAll(resp.Body)

		// Parse remote version
		re := regexp.MustCompile(`(?m)^#\s*@version\s+(.+)$`)
		matches := re.FindSubmatch(content)
		if len(matches) < 2 {
			fmt.Printf("  %-12s %-10s (no remote version)\n", p.Name, p.Metadata.Version)
			continue
		}

		remoteVersion := strings.TrimSpace(string(matches[1]))
		if CompareVersions(p.Metadata.Version, remoteVersion) < 0 {
			fmt.Printf("  %-12s %-10s -> %-10s \033[33m(update available)\033[0m\n",
				p.Name, p.Metadata.Version, remoteVersion)
			updatesAvailable = true
		} else {
			fmt.Printf("  %-12s %-10s (up to date)\n", p.Name, p.Metadata.Version)
		}
	}

	fmt.Println()
	if updatesAvailable {
		fmt.Println("Run 'prism plugin update <name>' or 'prism plugin update --all' to update.")
	} else {
		fmt.Println("All plugins are up to date.")
	}
}

// Update updates a specific plugin or all plugins
func (m *Manager) Update(target string) error {
	plugins, err := m.Discover()
	if err != nil {
		return err
	}

	if target == "--all" || target == "-a" {
		fmt.Println("Updating all plugins...")
		for _, p := range plugins {
			m.updatePlugin(p)
		}
		return nil
	}

	// Find specific plugin
	for _, p := range plugins {
		if p.Name == target {
			return m.updatePlugin(p)
		}
	}

	return fmt.Errorf("plugin '%s' not found", target)
}

func (m *Manager) updatePlugin(p Plugin) error {
	if p.Metadata.UpdateURL == "" {
		fmt.Printf("  %s: no update URL configured\n", p.Name)
		return nil
	}

	fmt.Printf("  %s: checking...\n", p.Name)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get(p.Metadata.UpdateURL)
	if err != nil {
		fmt.Printf("  %s: fetch failed\n", p.Name)
		return nil
	}
	defer resp.Body.Close()

	content, _ := io.ReadAll(resp.Body)

	// Parse remote version
	re := regexp.MustCompile(`(?m)^#\s*@version\s+(.+)$`)
	matches := re.FindSubmatch(content)
	if len(matches) < 2 {
		fmt.Printf("  %s: no version in remote file\n", p.Name)
		return nil
	}

	remoteVersion := strings.TrimSpace(string(matches[1]))
	if CompareVersions(p.Metadata.Version, remoteVersion) < 0 {
		if err := os.WriteFile(p.Path, content, 0755); err != nil {
			return fmt.Errorf("failed to update %s: %w", p.Name, err)
		}
		fmt.Printf("  %s: updated %s -> %s\n", p.Name, p.Metadata.Version, remoteVersion)
	} else {
		fmt.Printf("  %s: already up to date (%s)\n", p.Name, p.Metadata.Version)
	}

	return nil
}

// Remove uninstalls a plugin
func (m *Manager) Remove(name string) error {
	path := filepath.Join(m.pluginDir, fmt.Sprintf("prism-plugin-%s.sh", name))
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("plugin '%s' not found", name)
	}

	if err := os.Remove(path); err != nil {
		return fmt.Errorf("failed to remove plugin: %w", err)
	}

	fmt.Printf("Removed: %s\n", name)
	return nil
}

// CompareVersions compares two semver strings
// Returns -1 if a < b, 0 if a == b, 1 if a > b
func CompareVersions(a, b string) int {
	partsA := strings.Split(a, ".")
	partsB := strings.Split(b, ".")

	maxLen := len(partsA)
	if len(partsB) > maxLen {
		maxLen = len(partsB)
	}

	for i := 0; i < maxLen; i++ {
		var numA, numB int
		if i < len(partsA) {
			fmt.Sscanf(partsA[i], "%d", &numA)
		}
		if i < len(partsB) {
			fmt.Sscanf(partsB[i], "%d", &numB)
		}

		if numA < numB {
			return -1
		}
		if numA > numB {
			return 1
		}
	}

	return 0
}
