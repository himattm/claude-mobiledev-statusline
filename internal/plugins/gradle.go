package plugins

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// GradlePlugin shows Gradle daemon status
type GradlePlugin struct {
	cache *cache.Cache
}

func (p *GradlePlugin) Name() string {
	return "gradle"
}

func (p *GradlePlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

func (p *GradlePlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	projectDir := input.Prism.ProjectDir
	if projectDir == "" {
		return "", nil
	}

	cacheKey := fmt.Sprintf("gradle:%s", projectDir)

	// Check cache first
	if p.cache != nil {
		if cached, ok := p.cache.Get(cacheKey); ok {
			return cached, nil
		}
	}

	// Check if this is a Gradle project
	gradleFiles := []string{
		"build.gradle",
		"build.gradle.kts",
		"settings.gradle",
		"settings.gradle.kts",
	}

	isGradleProject := false
	for _, file := range gradleFiles {
		if _, err := os.Stat(filepath.Join(projectDir, file)); err == nil {
			isGradleProject = true
			break
		}
	}

	if !isGradleProject {
		return "", nil
	}

	// Count Gradle daemon processes
	count := countGradleDaemons(ctx)

	yellow := input.Colors["yellow"]
	reset := input.Colors["reset"]

	var result string
	if count > 0 {
		result = fmt.Sprintf("%s𓃰%d%s", yellow, count, reset)
	} else {
		result = fmt.Sprintf("%s𓃰?%s", yellow, reset)
	}

	// Cache for 2 seconds
	if p.cache != nil {
		p.cache.Set(cacheKey, result, cache.ProcessTTL)
	}

	return result, nil
}

func countGradleDaemons(ctx context.Context) int {
	cmd := exec.CommandContext(ctx, "pgrep", "-f", "GradleDaemon")
	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return 0
	}

	// Count lines in output
	output := strings.TrimSpace(out.String())
	if output == "" {
		return 0
	}

	return len(strings.Split(output, "\n"))
}
