package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var valueOptions = []string{"-o", "--output", "--build-type", "--timeout", "--filter", "--cpu-profile", "--heap-profile", "--trace"}

func splitCommandValueOption(command, arg string) (name, value string, inline bool) {
	// A profile bundle owns its artifact paths; --trace=<path> belongs to run.
	// Preserve the token so it cannot become a bare profile tracing request.
	if command == "profile" && strings.HasPrefix(arg, "--trace=") {
		return arg, "", false
	}
	return splitValueOption(arg, valueOptions...)
}

// splitValueOption recognizes only long options that take values. Keep unknown
// tokens intact for diagnostics, and split once so paths and text can contain '='.
func splitValueOption(arg string, options ...string) (name, value string, inline bool) {
	name, value, inline = strings.Cut(arg, "=")
	if inline && strings.HasPrefix(name, "--") {
		for _, option := range options {
			if name == option {
				return name, value, true
			}
		}
	}
	return arg, "", false
}

// requiredValue consumes a split value or uses its inline spelling. Empty
// required values are usage errors in either form.
func requiredValue(args []string, index *int, value string, inline bool) (string, bool) {
	if !inline {
		*index += 1
		if *index == len(args) {
			return "", false
		}
		value = args[*index]
	}
	return value, value != ""
}

func resolveInput(command, filename string) (string, error) {
	if info, err := os.Stat(filename); err == nil && info.IsDir() {
		manifest := filepath.Join(filename, "ms.toml")
		if _, err := os.Stat(manifest); err != nil {
			return "", fmt.Errorf("ms %s: %s is a directory without an ms.toml; pass a .ms file or a project ms.toml, e.g. ms %s ms.toml", command, filename, command)
		}
		return manifest, nil
	}
	return filename, nil
}
