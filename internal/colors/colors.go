package colors

import "fmt"

// ANSI color codes
const (
	Reset   = "\033[0m"
	Cyan    = "\033[36m"
	Green   = "\033[32m"
	Yellow  = "\033[33m"
	Red     = "\033[31m"
	Magenta = "\033[35m"
	Blue    = "\033[34m"
	Gray    = "\033[90m"
	Dim     = "\033[2m"
)

// ColorMap returns all colors as a map for plugin input
func ColorMap() map[string]string {
	return map[string]string{
		"cyan":    Cyan,
		"green":   Green,
		"yellow":  Yellow,
		"red":     Red,
		"magenta": Magenta,
		"blue":    Blue,
		"gray":    Gray,
		"dim":     Dim,
		"reset":   Reset,
	}
}

// Wrap wraps text in color codes
func Wrap(color, text string) string {
	return fmt.Sprintf("%s%s%s", color, text, Reset)
}

// Separator returns the status line separator
func Separator() string {
	return fmt.Sprintf(" %s·%s ", Dim, Reset)
}
