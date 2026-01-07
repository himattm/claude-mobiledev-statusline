package plugins

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// XcodePlugin shows Xcode build status
type XcodePlugin struct {
	cache *cache.Cache
}

func (p *XcodePlugin) Name() string {
	return "xcode"
}

func (p *XcodePlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

func (p *XcodePlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	projectDir := input.Prism.ProjectDir
	if projectDir == "" {
		return "", nil
	}

	cacheKey := fmt.Sprintf("xcode:%s", projectDir)

	// Check cache first
	if p.cache != nil {
		if cached, ok := p.cache.Get(cacheKey); ok {
			return cached, nil
		}
	}

	// Check if this is an Xcode project
	xcodeProjects, _ := filepath.Glob(filepath.Join(projectDir, "*.xcodeproj"))
	xcodeWorkspaces, _ := filepath.Glob(filepath.Join(projectDir, "*.xcworkspace"))

	if len(xcodeProjects) == 0 && len(xcodeWorkspaces) == 0 {
		return "", nil
	}

	// Count xcodebuild processes
	count := countXcodeBuildProcesses(ctx)

	if count == 0 {
		return "", nil
	}

	yellow := input.Colors["yellow"]
	reset := input.Colors["reset"]

	var result string
	if count > 1 {
		result = fmt.Sprintf("%s⚒%d%s", yellow, count, reset)
	} else {
		result = fmt.Sprintf("%s⚒%s", yellow, reset)
	}

	// Cache for 2 seconds
	if p.cache != nil {
		p.cache.Set(cacheKey, result, cache.ProcessTTL)
	}

	return result, nil
}

func countXcodeBuildProcesses(ctx context.Context) int {
	cmd := exec.CommandContext(ctx, "pgrep", "-f", "xcodebuild")
	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return 0
	}

	output := strings.TrimSpace(out.String())
	if output == "" {
		return 0
	}

	return len(strings.Split(output, "\n"))
}
