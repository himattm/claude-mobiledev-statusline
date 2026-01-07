package statusline

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/himattm/prism/internal/colors"
	"github.com/himattm/prism/internal/config"
	"github.com/himattm/prism/internal/plugin"
	"github.com/himattm/prism/internal/plugins"
)

const Version = "0.2.0"

// StatusLine handles rendering the status line
type StatusLine struct {
	input           Input
	config          config.Config
	pluginManager   *plugin.Manager
	nativePlugins   *plugins.Registry
	isIdle          bool
	bashPlugins     []plugin.Plugin // Cached discovered bash plugins
	bashPluginsOnce sync.Once
}

// New creates a new StatusLine renderer
func New(input Input, cfg config.Config) *StatusLine {
	return &StatusLine{
		input:         input,
		config:        cfg,
		pluginManager: plugin.NewManager(),
		nativePlugins: plugins.NewRegistry(),
		isIdle:        checkIsIdle(input.SessionID),
	}
}

// discoverBashPlugins discovers bash plugins once and caches them
func (sl *StatusLine) discoverBashPlugins() []plugin.Plugin {
	sl.bashPluginsOnce.Do(func() {
		discovered, err := sl.pluginManager.Discover()
		if err == nil {
			sl.bashPlugins = discovered
		}
	})
	return sl.bashPlugins
}

func checkIsIdle(sessionID string) bool {
	idleFile := filepath.Join(os.TempDir(), fmt.Sprintf("prism-idle-%s", sessionID))
	if _, err := os.Stat(idleFile); err == nil {
		return true
	}
	// Check if any idle files exist (hooks are active)
	matches, _ := filepath.Glob(filepath.Join(os.TempDir(), "prism-idle-*"))
	if len(matches) > 0 {
		return false
	}
	// No idle files = hooks not set up, assume idle
	return true
}

// Render generates the status line output
func (sl *StatusLine) Render() string {
	lines := sl.config.GetAllSectionLines()
	var output []string

	for i, sections := range lines {
		line := sl.renderLine(sections)
		if line != "" {
			// Prepend update indicator to first line only
			if i == 0 {
				updateOutput := sl.runUpdatePlugin()
				if updateOutput != "" {
					line = updateOutput + colors.Separator() + line
				}
			}
			output = append(output, line)
		}
	}

	return strings.Join(output, "\n")
}

func (sl *StatusLine) renderLine(sections []string) string {
	// Run all sections in parallel
	type result struct {
		index  int
		output string
	}

	results := make([]string, len(sections))
	var wg sync.WaitGroup

	for i, section := range sections {
		wg.Add(1)
		go func(idx int, sec string) {
			defer wg.Done()
			results[idx] = sl.renderSection(sec)
		}(i, section)
	}

	wg.Wait()

	// Filter empty and join (preserving order)
	var parts []string
	for _, out := range results {
		if out != "" {
			parts = append(parts, out)
		}
	}

	return strings.Join(parts, colors.Separator())
}

func (sl *StatusLine) renderSection(section string) string {
	switch section {
	case "dir":
		return sl.renderDir()
	case "model":
		return sl.renderModel()
	case "context":
		return sl.renderContext()
	case "linesChanged":
		return sl.renderLinesChanged()
	case "cost":
		return sl.renderCost()
	case "git":
		return sl.runPlugin("git")
	case "devices":
		return sl.runPlugin("devices")
	case "gradle":
		return sl.runPlugin("gradle")
	case "xcode":
		return sl.runPlugin("xcode")
	case "mcp":
		return sl.runPlugin("mcp")
	default:
		// Try to run as plugin
		return sl.runPlugin(section)
	}
}

func (sl *StatusLine) renderDir() string {
	projectName := filepath.Base(sl.input.Workspace.ProjectDir)
	icon := sl.config.Icon
	if icon != "" {
		icon += " "
	}

	// Calculate subdir if current differs from project
	subdir := ""
	if sl.input.Workspace.CurrentDir != "" && sl.input.Workspace.ProjectDir != "" {
		if strings.HasPrefix(sl.input.Workspace.CurrentDir, sl.input.Workspace.ProjectDir) {
			subdir = strings.TrimPrefix(sl.input.Workspace.CurrentDir, sl.input.Workspace.ProjectDir)
		}
	}

	if subdir != "" {
		return fmt.Sprintf("%s%s%s%s%s%s",
			icon, colors.Dim, colors.Cyan, projectName, colors.Reset,
			colors.Wrap(colors.Cyan, subdir))
	}

	return fmt.Sprintf("%s%s", icon, colors.Wrap(colors.Cyan, projectName))
}

func (sl *StatusLine) renderModel() string {
	return colors.Wrap(colors.Magenta, sl.input.Model.DisplayName)
}

func (sl *StatusLine) renderContext() string {
	usage := sl.input.Context.CurrentUsage
	windowSize := sl.input.Context.ContextWindow
	if windowSize == 0 {
		windowSize = 200000 // Default
	}

	// Calculate percentage with overhead estimate
	const overhead = 10000
	totalTokens := usage.InputTokens + usage.OutputTokens +
		usage.CacheCreationTokens + usage.CacheReadTokens + overhead
	pct := (totalTokens * 100) / windowSize

	return renderContextBar(pct)
}

func renderContextBar(pct int) string {
	// 10-char bar: [████░░░░▒▒]
	const barLen = 10
	filled := (pct * barLen) / 100
	if filled > barLen {
		filled = barLen
	}

	// Warning zone starts at 80%
	warningStart := 8

	var bar strings.Builder
	bar.WriteString("[")

	for i := 0; i < barLen; i++ {
		if i < filled {
			bar.WriteString("█")
		} else if i >= warningStart {
			bar.WriteString("▒")
		} else {
			bar.WriteString("░")
		}
	}

	bar.WriteString(fmt.Sprintf("] %d%%", pct))
	return bar.String()
}

func (sl *StatusLine) renderLinesChanged() string {
	// ALWAYS use git diff stats - never use Claude's session stats
	// This shows actual uncommitted changes in the working tree
	added, removed := getGitDiffStats(sl.input.Workspace.ProjectDir)

	return fmt.Sprintf("%s+%d%s %s-%d%s",
		colors.Green, added, colors.Reset,
		colors.Red, removed, colors.Reset)
}

func getGitDiffStats(projectDir string) (int, int) {
	if projectDir == "" {
		return 0, 0
	}

	cmd := exec.Command("git", "diff", "--numstat", "HEAD")
	cmd.Dir = projectDir
	output, err := cmd.Output()
	if err != nil {
		return 0, 0
	}

	var added, removed int
	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		var a, r int
		fmt.Sscanf(line, "%d\t%d", &a, &r)
		added += a
		removed += r
	}

	return added, removed
}

func (sl *StatusLine) renderCost() string {
	cost := sl.input.Cost.TotalCostUSD
	return colors.Wrap(colors.Gray, fmt.Sprintf("$%.2f", cost))
}

func (sl *StatusLine) runPlugin(name string) string {
	// Build plugin input
	input := plugin.Input{
		Prism: plugin.PrismContext{
			Version:    Version,
			ProjectDir: sl.input.Workspace.ProjectDir,
			CurrentDir: sl.input.Workspace.CurrentDir,
			SessionID:  sl.input.SessionID,
			IsIdle:     sl.isIdle,
		},
		Session: plugin.SessionContext{
			Model:        sl.input.Model.DisplayName,
			ContextPct:   sl.calculateContextPct(),
			CostUSD:      sl.input.Cost.TotalCostUSD,
			LinesAdded:   sl.input.Cost.TotalLinesAdded,
			LinesRemoved: sl.input.Cost.TotalLinesRemoved,
		},
		Config: sl.getPluginConfig(name),
		Colors: colors.ColorMap(),
	}

	// Try native plugin first (much faster - no subprocess)
	if native := sl.nativePlugins.Get(name); native != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancel()

		output, err := native.Execute(ctx, input)
		if err == nil {
			return output
		}
		// Fall through to bash plugin on error
	}

	// Fall back to bash plugin
	return sl.runBashPlugin(name, input)
}

func (sl *StatusLine) runBashPlugin(name string, input plugin.Input) string {
	bashPlugins := sl.discoverBashPlugins()

	var targetPlugin *plugin.Plugin
	for _, p := range bashPlugins {
		if p.Name == name {
			targetPlugin = &p
			break
		}
	}

	if targetPlugin == nil {
		return ""
	}

	output, err := sl.pluginManager.Execute(*targetPlugin, input, 500*time.Millisecond)
	if err != nil {
		return ""
	}

	return output
}

func (sl *StatusLine) runUpdatePlugin() string {
	return sl.runPlugin("update")
}

func (sl *StatusLine) calculateContextPct() int {
	usage := sl.input.Context.CurrentUsage
	windowSize := sl.input.Context.ContextWindow
	if windowSize == 0 {
		windowSize = 200000
	}

	const overhead = 10000
	totalTokens := usage.InputTokens + usage.OutputTokens +
		usage.CacheCreationTokens + usage.CacheReadTokens + overhead

	return (totalTokens * 100) / windowSize
}

func (sl *StatusLine) getPluginConfig(name string) map[string]any {
	if sl.config.Plugins == nil {
		return map[string]any{name: map[string]any{}}
	}
	if cfg, ok := sl.config.Plugins[name]; ok {
		return map[string]any{name: cfg}
	}
	return map[string]any{name: map[string]any{}}
}
