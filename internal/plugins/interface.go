package plugins

import (
	"context"

	"github.com/himattm/prism/internal/cache"
	"github.com/himattm/prism/internal/plugin"
)

// NativePlugin defines the interface for built-in Go plugins
type NativePlugin interface {
	Name() string
	Execute(ctx context.Context, input plugin.Input) (string, error)
	SetCache(c *cache.Cache)
}

// Registry holds all available native plugins
type Registry struct {
	plugins map[string]NativePlugin
	cache   *cache.Cache
}

// NewRegistry creates a new plugin registry with all native plugins
func NewRegistry() *Registry {
	c := cache.New()
	r := &Registry{
		plugins: make(map[string]NativePlugin),
		cache:   c,
	}

	// Register native plugins with shared cache
	r.registerWithCache(&MCPPlugin{})
	r.registerWithCache(&GradlePlugin{})
	r.registerWithCache(&XcodePlugin{})
	r.registerWithCache(&GitPlugin{})
	r.registerWithCache(&UpdatePlugin{})

	return r
}

func (r *Registry) registerWithCache(p NativePlugin) {
	p.SetCache(r.cache)
	r.plugins[p.Name()] = p
}

// Register adds a plugin to the registry
func (r *Registry) Register(p NativePlugin) {
	r.plugins[p.Name()] = p
}

// Get returns a native plugin by name, or nil if not found
func (r *Registry) Get(name string) NativePlugin {
	return r.plugins[name]
}

// Has returns true if a native plugin exists for the given name
func (r *Registry) Has(name string) bool {
	_, ok := r.plugins[name]
	return ok
}
