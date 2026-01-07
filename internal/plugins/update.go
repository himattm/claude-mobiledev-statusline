package plugins

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

const (
	updateCheckURL  = "https://raw.githubusercontent.com/himattm/prism/main/prism.sh"
	updateCacheTTL  = 24 * time.Hour
	updateCacheFile = "prism-update-check"
)

// UpdatePlugin shows indicator when Prism update is available
type UpdatePlugin struct {
	cache *cache.Cache
}

type updateCache struct {
	CheckedAt     int64  `json:"checked_at"`
	LatestVersion string `json:"latest_version"`
	UpdateAvail   bool   `json:"update_available"`
}

func (p *UpdatePlugin) Name() string {
	return "update"
}

func (p *UpdatePlugin) SetCache(c *cache.Cache) {
	p.cache = c
}

func (p *UpdatePlugin) Execute(ctx context.Context, input plugin.Input) (string, error) {
	// Get config
	enabled := true
	checkInterval := updateCacheTTL
	if cfg, ok := input.Config["update"].(map[string]any); ok {
		if e, ok := cfg["enabled"].(bool); ok {
			enabled = e
		}
		if hours, ok := cfg["check_interval_hours"].(float64); ok {
			checkInterval = time.Duration(hours) * time.Hour
		}
	}

	if !enabled {
		return "", nil
	}

	// Check file-based cache first
	cacheData, cacheExists := loadUpdateCache()

	// If cache exists and is fresh, use it
	if cacheExists {
		age := time.Since(time.Unix(cacheData.CheckedAt, 0))
		if age < checkInterval {
			if cacheData.UpdateAvail {
				return formatUpdateIndicator(input.Colors), nil
			}
			return "", nil
		}
	}

	// Only refresh when idle (to avoid blocking during active use)
	if !input.Prism.IsIdle && cacheExists {
		// Return stale cache data while not idle
		if cacheData.UpdateAvail {
			return formatUpdateIndicator(input.Colors), nil
		}
		return "", nil
	}

	// Fetch latest version (with timeout)
	fetchCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	latestVersion, err := fetchLatestVersion(fetchCtx)
	if err != nil {
		// On error, use stale cache if available
		if cacheExists && cacheData.UpdateAvail {
			return formatUpdateIndicator(input.Colors), nil
		}
		return "", nil
	}

	// Compare versions
	currentVersion := input.Prism.Version
	updateAvail := compareVersions(currentVersion, latestVersion) < 0

	// Save to cache
	saveUpdateCache(updateCache{
		CheckedAt:     time.Now().Unix(),
		LatestVersion: latestVersion,
		UpdateAvail:   updateAvail,
	})

	if updateAvail {
		return formatUpdateIndicator(input.Colors), nil
	}
	return "", nil
}

func formatUpdateIndicator(colors map[string]string) string {
	yellow := colors["yellow"]
	reset := colors["reset"]
	return fmt.Sprintf("%s⬆%s", yellow, reset)
}

func fetchLatestVersion(ctx context.Context) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", updateCheckURL, nil)
	if err != nil {
		return "", err
	}

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// Read first 2KB to find VERSION
	buf := make([]byte, 2048)
	n, _ := resp.Body.Read(buf)
	content := string(buf[:n])

	// Extract VERSION="x.y.z"
	re := regexp.MustCompile(`VERSION="([0-9]+\.[0-9]+\.[0-9]+)"`)
	matches := re.FindStringSubmatch(content)
	if len(matches) < 2 {
		return "", fmt.Errorf("version not found")
	}

	return matches[1], nil
}

func loadUpdateCache() (updateCache, bool) {
	path := filepath.Join(os.TempDir(), updateCacheFile)
	data, err := os.ReadFile(path)
	if err != nil {
		return updateCache{}, false
	}

	var cache updateCache
	if err := json.Unmarshal(data, &cache); err != nil {
		return updateCache{}, false
	}

	return cache, true
}

func saveUpdateCache(c updateCache) {
	path := filepath.Join(os.TempDir(), updateCacheFile)
	data, err := json.Marshal(c)
	if err != nil {
		return
	}
	os.WriteFile(path, data, 0644)
}

// compareVersions compares two semver strings
// Returns -1 if a < b, 0 if a == b, 1 if a > b
func compareVersions(a, b string) int {
	partsA := strings.Split(a, ".")
	partsB := strings.Split(b, ".")

	maxLen := len(partsA)
	if len(partsB) > maxLen {
		maxLen = len(partsB)
	}

	for i := 0; i < maxLen; i++ {
		var numA, numB int
		if i < len(partsA) {
			numA, _ = strconv.Atoi(partsA[i])
		}
		if i < len(partsB) {
			numB, _ = strconv.Atoi(partsB[i])
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
