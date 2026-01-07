package plugins

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// GitPlugin shows git branch and status
type GitPlugin struct {
	cache *cache.Cache
}

func (p *GitPlugin) Name() string {
	return "git"
}

func (p *GitPlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

func (p *GitPlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	projectDir := input.Prism.ProjectDir
	if projectDir == "" {
		return "", nil
	}

	cacheKey := fmt.Sprintf("git:%s", projectDir)

	// Check cache first (only when not idle - allow refresh when idle)
	if p.cache != nil && !input.Prism.IsIdle {
		if cached, ok := p.cache.Get(cacheKey); ok {
			return cached, nil
		}
	}

	// Check if this is a git repo
	if !isGitRepo(ctx, projectDir) {
		return "", nil
	}

	// Get branch name
	branch := getGitBranch(ctx, projectDir)
	if branch == "" {
		return "", nil
	}

	// Get dirty status
	dirty := getGitDirty(ctx, projectDir)

	// Get upstream status
	behind, ahead := getUpstreamStatus(ctx, projectDir)

	// Format output
	yellow := input.Colors["yellow"]
	reset := input.Colors["reset"]

	var result strings.Builder
	result.WriteString(yellow)
	result.WriteString(branch)

	if dirty != "" {
		result.WriteString(dirty)
	}

	if behind > 0 {
		result.WriteString(fmt.Sprintf(" ⇣%d", behind))
	}
	if ahead > 0 {
		result.WriteString(fmt.Sprintf(" ⇡%d", ahead))
	}

	result.WriteString(reset)
	output := result.String()

	// Cache for 2 seconds
	if p.cache != nil {
		p.cache.Set(cacheKey, output, cache.GitTTL)
	}

	return output, nil
}

func isGitRepo(ctx context.Context, dir string) bool {
	cmd := exec.CommandContext(ctx, "git", "rev-parse", "--git-dir")
	cmd.Dir = dir
	return cmd.Run() == nil
}

func getGitBranch(ctx context.Context, dir string) string {
	// Try to get current branch
	cmd := exec.CommandContext(ctx, "git", "branch", "--show-current")
	cmd.Dir = dir
	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return ""
	}

	branch := strings.TrimSpace(out.String())
	if branch != "" {
		return branch
	}

	// Detached HEAD - get short commit
	cmd = exec.CommandContext(ctx, "git", "rev-parse", "--short", "HEAD")
	cmd.Dir = dir
	out.Reset()
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return ""
	}

	return strings.TrimSpace(out.String())
}

func getGitDirty(ctx context.Context, dir string) string {
	cmd := exec.CommandContext(ctx, "git", "status", "--porcelain")
	cmd.Dir = dir
	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return ""
	}

	output := out.String()
	if output == "" {
		return ""
	}

	var dirty strings.Builder
	hasStaged := false
	hasUnstaged := false
	hasUntracked := false

	lines := strings.Split(strings.TrimSpace(output), "\n")
	for _, line := range lines {
		if len(line) < 2 {
			continue
		}

		index := line[0]
		worktree := line[1]

		// Check for staged changes (index not empty and not '?')
		if index != ' ' && index != '?' {
			hasStaged = true
		}

		// Check for unstaged changes (worktree modified)
		if worktree != ' ' && worktree != '?' {
			hasUnstaged = true
		}

		// Check for untracked files
		if index == '?' {
			hasUntracked = true
		}
	}

	if hasStaged {
		dirty.WriteString("*")
	}
	if hasUnstaged {
		dirty.WriteString("*")
	}
	if hasUntracked {
		dirty.WriteString("+")
	}

	return dirty.String()
}

func getUpstreamStatus(ctx context.Context, dir string) (behind, ahead int) {
	// Get commits behind upstream
	cmd := exec.CommandContext(ctx, "git", "rev-list", "--count", "HEAD..@{upstream}")
	cmd.Dir = dir
	var out bytes.Buffer
	cmd.Stdout = &out

	if cmd.Run() == nil {
		behind, _ = strconv.Atoi(strings.TrimSpace(out.String()))
	}

	// Get commits ahead of upstream
	cmd = exec.CommandContext(ctx, "git", "rev-list", "--count", "@{upstream}..HEAD")
	cmd.Dir = dir
	out.Reset()
	cmd.Stdout = &out

	if cmd.Run() == nil {
		ahead, _ = strconv.Atoi(strings.TrimSpace(out.String()))
	}

	return behind, ahead
}
