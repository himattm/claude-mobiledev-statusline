package plugins

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// WorktreePlugin shows which git worktree you're in
type WorktreePlugin struct {
	cache *cache.Cache
}

func (p *WorktreePlugin) Name() string {
	return "worktree"
}

func (p *WorktreePlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

// OnHook invalidates cache when Claude becomes idle
func (p *WorktreePlugin) OnHook(ctx context.Context, hookType HookType, hookCtx HookContext) (string, error) {
	if hookType == HookIdle && p.cache != nil {
		p.cache.DeleteByPrefix("worktree:")
	}
	return "", nil
}

func (p *WorktreePlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	projectDir := input.Prism.ProjectDir
	if projectDir == "" {
		return "", nil
	}

	cacheKey := fmt.Sprintf("worktree:%s", projectDir)
	if p.cache != nil {
		if cached, ok := p.cache.Get(cacheKey); ok {
			return cached, nil
		}
	}

	// Check if we're in a worktree by examining .git
	// Main repo: .git is a directory
	// Worktree: .git is a file containing "gitdir: /path/to/.git/worktrees/<name>"
	gitPath := filepath.Join(projectDir, ".git")
	info, err := os.Stat(gitPath)
	if err != nil {
		return "", nil // Not a git repo
	}

	if info.IsDir() {
		// Main repo, not a worktree - show nothing
		if p.cache != nil {
			p.cache.Set(cacheKey, "", cache.GitTTL)
		}
		return "", nil
	}

	// It's a file - we're in a worktree
	content, err := os.ReadFile(gitPath)
	if err != nil {
		return "", nil
	}

	// Parse: gitdir: /path/to/.git/worktrees/<name>
	line := strings.TrimSpace(string(content))
	if !strings.HasPrefix(line, "gitdir: ") {
		return "", nil
	}

	gitDir := strings.TrimPrefix(line, "gitdir: ")

	// Extract worktree name from path
	// Format: /path/to/main/.git/worktrees/<worktree-name>
	worktreeName := filepath.Base(gitDir)
	if worktreeName == "" || worktreeName == "." {
		return "", nil
	}

	// Get config for custom icon
	icon := "⌂"
	if cfg, ok := input.Config["worktree"].(map[string]any); ok {
		if customIcon, ok := cfg["icon"].(string); ok && customIcon != "" {
			icon = customIcon
		}
	}

	// Format output: dim icon + purple worktree name
	purple := input.Colors["purple"]
	dim := input.Colors["dim"]
	reset := input.Colors["reset"]

	result := fmt.Sprintf("%s%s %s%s%s", dim, icon, purple, worktreeName, reset)

	if p.cache != nil {
		p.cache.Set(cacheKey, result, cache.GitTTL)
	}

	return result, nil
}
