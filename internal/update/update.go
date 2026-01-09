package update

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/himattm/prism/internal/version"
)

const (
	releasesURL = "https://api.github.com/repos/himattm/prism/releases/latest"
)

// Info contains update check results
type Info struct {
	CurrentVersion  string
	LatestVersion   string
	UpdateAvailable bool
}

// Check fetches the latest version and compares with current
func Check(ctx context.Context) (*Info, error) {
	latest, err := fetchLatestVersion(ctx)
	if err != nil {
		return nil, err
	}

	return &Info{
		CurrentVersion:  version.Version,
		LatestVersion:   latest,
		UpdateAvailable: compareVersions(version.Version, latest) < 0,
	}, nil
}

// Download fetches and installs the latest binary
func Download(ctx context.Context) error {
	// Determine binary URL
	osName := runtime.GOOS
	arch := runtime.GOARCH

	binaryURL := fmt.Sprintf("https://github.com/himattm/prism/releases/latest/download/prism-%s-%s", osName, arch)

	// Get the path to current binary
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("failed to get home directory: %w", err)
	}
	binaryPath := filepath.Join(homeDir, ".claude", "prism")
	tempPath := binaryPath + ".new"

	// Download to temp file
	req, err := http.NewRequestWithContext(ctx, "GET", binaryURL, nil)
	if err != nil {
		return err
	}

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return fmt.Errorf("binary not found for %s/%s (release may not include this platform)", osName, arch)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
	}

	// Write to temp file
	out, err := os.Create(tempPath)
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}

	_, err = io.Copy(out, resp.Body)
	out.Close()
	if err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to write file: %w", err)
	}

	// Make executable
	if err := os.Chmod(tempPath, 0755); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to chmod: %w", err)
	}

	// Atomic replace
	if err := os.Rename(tempPath, binaryPath); err != nil {
		os.Remove(tempPath)
		return fmt.Errorf("failed to install: %w", err)
	}

	return nil
}

func fetchLatestVersion(ctx context.Context) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", releasesURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("no releases found (releases not yet published)")
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	var release struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return "", err
	}

	// Strip leading 'v' if present
	ver := strings.TrimPrefix(release.TagName, "v")
	if ver == "" {
		return "", fmt.Errorf("version not found in release")
	}

	return ver, nil
}

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
