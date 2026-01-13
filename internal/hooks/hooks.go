package hooks

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/himattm/prism/internal/config"
	"github.com/himattm/prism/internal/plugins"
)

// Input represents the JSON input from Claude Code hooks
type Input struct {
	SessionID string `json:"session_id"`
}

// Manager handles hook execution
type Manager struct {
	registry *plugins.Registry
}

// NewManager creates a new hook manager
func NewManager() *Manager {
	return &Manager{
		registry: plugins.NewRegistry(),
	}
}

// HandleIdle processes the idle hook (called when Claude stops responding)
func (m *Manager) HandleIdle(input Input) error {
	// 1. Create idle marker file
	if input.SessionID != "" {
		idleFile := filepath.Join(os.TempDir(), fmt.Sprintf("prism-idle-%s", input.SessionID))
		if err := os.WriteFile(idleFile, []byte{}, 0644); err != nil {
			return err
		}
	}

	// 2. Load config for plugins
	cfg := config.Load("")
	pluginConfig := make(map[string]any)
	if cfg.Plugins != nil {
		pluginConfig = cfg.Plugins
	}

	// 3. Run hooks on all hookable plugins
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hookCtx := plugins.HookContext{
		SessionID: input.SessionID,
		Config:    pluginConfig,
	}

	outputs := m.registry.RunHooks(ctx, plugins.HookIdle, hookCtx)

	// 4. Print any outputs (for Claude Code to display)
	if len(outputs) > 0 {
		fmt.Print(strings.Join(outputs, "\n"))
	}

	return nil
}

// HandleBusy processes the busy hook (called when user submits prompt)
func (m *Manager) HandleBusy(input Input) error {
	// 1. Remove idle marker file
	if input.SessionID != "" {
		idleFile := filepath.Join(os.TempDir(), fmt.Sprintf("prism-idle-%s", input.SessionID))
		os.Remove(idleFile) // Ignore error if doesn't exist
	}

	// 2. Load config for plugins
	cfg := config.Load("")
	pluginConfig := make(map[string]any)
	if cfg.Plugins != nil {
		pluginConfig = cfg.Plugins
	}

	// 3. Run hooks on all hookable plugins
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hookCtx := plugins.HookContext{
		SessionID: input.SessionID,
		Config:    pluginConfig,
	}

	outputs := m.registry.RunHooks(ctx, plugins.HookBusy, hookCtx)

	// 4. Print any outputs (for notifications)
	if len(outputs) > 0 {
		fmt.Print(strings.Join(outputs, "\n"))
	}

	return nil
}

// HandleSessionStart processes the session start hook
func (m *Manager) HandleSessionStart(input Input) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hookCtx := plugins.HookContext{
		SessionID: input.SessionID,
	}

	outputs := m.registry.RunHooks(ctx, plugins.HookSessionStart, hookCtx)

	if len(outputs) > 0 {
		fmt.Print(strings.Join(outputs, "\n"))
	}

	return nil
}

// HandleSessionEnd processes the session end hook
func (m *Manager) HandleSessionEnd(input Input) error {
	// Clean up idle marker file
	if input.SessionID != "" {
		idleFile := filepath.Join(os.TempDir(), fmt.Sprintf("prism-idle-%s", input.SessionID))
		os.Remove(idleFile)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hookCtx := plugins.HookContext{
		SessionID: input.SessionID,
	}

	outputs := m.registry.RunHooks(ctx, plugins.HookSessionEnd, hookCtx)

	if len(outputs) > 0 {
		fmt.Print(strings.Join(outputs, "\n"))
	}

	return nil
}

// HandlePreCompact processes the pre-compact hook
func (m *Manager) HandlePreCompact(input Input) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	hookCtx := plugins.HookContext{
		SessionID: input.SessionID,
	}

	outputs := m.registry.RunHooks(ctx, plugins.HookPreCompact, hookCtx)

	if len(outputs) > 0 {
		fmt.Print(strings.Join(outputs, "\n"))
	}

	return nil
}
