package plugins

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// MCPPlugin shows MCP server count
type MCPPlugin struct {
	cache *cache.Cache
}

func (p *MCPPlugin) Name() string {
	return "mcp"
}

func (p *MCPPlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

func (p *MCPPlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	cacheKey := fmt.Sprintf("mcp:%s", input.Prism.ProjectDir)

	// Check cache first
	if p.cache != nil {
		if cached, ok := p.cache.Get(cacheKey); ok {
			return cached, nil
		}
	}

	// Read global config (~/.claude.json)
	homeDir, _ := os.UserHomeDir()
	globalPath := filepath.Join(homeDir, ".claude.json")
	globalCount := countMCPServers(globalPath)

	// Read project config (.mcp.json)
	projectPath := filepath.Join(input.Prism.ProjectDir, ".mcp.json")
	projectCount := countMCPServers(projectPath)

	total := globalCount + projectCount
	if total == 0 {
		return "", nil
	}

	gray := input.Colors["gray"]
	reset := input.Colors["reset"]
	result := fmt.Sprintf("%smcp:%d%s", gray, total, reset)

	// Cache for 10 seconds
	if p.cache != nil {
		p.cache.Set(cacheKey, result, cache.ConfigTTL)
	}

	return result, nil
}

func countMCPServers(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}

	var config struct {
		MCPServers map[string]any `json:"mcpServers"`
	}

	if err := json.Unmarshal(data, &config); err != nil {
		return 0
	}

	return len(config.MCPServers)
}
