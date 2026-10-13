package compiler

import (
	"encoding/json"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

// goCommand keeps toolchain discovery and environment identical for pins and builds.
func goCommand(arguments ...string) (*exec.Cmd, error) {
	tool, root, environment, err := goToolchain()
	if err != nil {
		return nil, err
	}
	if _, err := os.Stat(tool); err != nil && root != "" {
		// The bundled SDK has no go command; only the built-in tools can use it.
		if reason := gotoolchain.Supported(root); reason != nil {
			return nil, fmt.Errorf("cannot build with %s: %w", root, reason)
		}
	}
	command := exec.Command(tool, arguments...)
	command.Env = environment
	return command, nil
}

// goToolchain selects the go executable, its SDK root when it can be found
// without running it, and the environment for builds.
func goToolchain() (string, string, []string, error) {
	tool := os.Getenv("MANUSCRIPT_GO")
	root := ""
	settings := map[string]string{"GOTOOLCHAIN": "local", "CGO_ENABLED": "0", "GOENV": "off"}
	if tool == "" {
		if len(support.GoToolchainArchive) != 0 {
			var err error
			root, err = bundledGoRoot()
			if err != nil {
				return "", "", nil, fmt.Errorf("prepare bundled toolchain: %w", err)
			}
			tool = goExecutable(root)
			settings["GOROOT"] = root
		} else {
			// Preserve direct go build and library embedding for developers.
			var err error
			tool, err = exec.LookPath("go")
			if err != nil {
				return "", "", nil, fmt.Errorf("this developer binary has no bundled toolchain; use a Manuscript release binary, run make build, or set MANUSCRIPT_GO: %w", err)
			}
		}
	}
	if root == "" {
		root = sdkRoot(tool)
	}
	var environment []string
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if _, replaced := settings[strings.ToUpper(key)]; !replaced {
			environment = append(environment, entry)
		}
	}
	for _, key := range slices.Sorted(maps.Keys(settings)) {
		environment = append(environment, key+"="+settings[key])
	}
	return tool, root, environment, nil
}

// sdkRoot finds the SDK containing a go executable at bin/go, or returns "".
func sdkRoot(tool string) string {
	if resolved, err := filepath.EvalSymlinks(tool); err == nil {
		tool = resolved
	}
	root := filepath.Dir(filepath.Dir(tool))
	if _, err := os.Stat(filepath.Join(root, "src", "runtime")); err != nil {
		return ""
	}
	return root
}

// nativeToolchain returns the SDK root and build environment when ms's
// built-in Go tools can build with the selected SDK. Builds then run no go
// command; otherwise they use the selected go executable.
func nativeToolchain() (string, []string, bool) {
	_, root, environment, err := goToolchain()
	if err != nil || root == "" || gotoolchain.Supported(root) != nil {
		return "", nil, false
	}
	return root, environment, true
}

// Toolchain queries are remembered per tool and environment, so one process
// that pins and builds (or prefetches its pin) runs go env only once.
var toolchainQueries sync.Map

type toolchainQuery struct {
	sync.Once
	toolchain map[string]string
	err       error
}

func queryToolchain() (map[string]string, error) {
	if _, _, ok := nativeToolchain(); ok {
		return gotoolchain.Environment(), nil
	}
	command, err := goCommand("env", "-json", "GOVERSION", "GOOS", "GOARCH", "CGO_ENABLED", "GOEXPERIMENT", "GOFLAGS", "GOAMD64", "GOARM", "GOARM64", "GOMIPS", "GOMIPS64", "GOPPC64", "GORISCV64", "GOWASM")
	if err != nil {
		return nil, err
	}
	key := command.Path + "\x00" + strings.Join(command.Env, "\x00")
	entry, _ := toolchainQueries.LoadOrStore(key, &toolchainQuery{})
	query := entry.(*toolchainQuery)
	query.Do(func() {
		data, err := command.CombinedOutput()
		if err != nil {
			query.err = fmt.Errorf("read Go toolchain: %w: %s", err, data)
			return
		}
		query.err = json.Unmarshal(data, &query.toolchain)
	})
	if query.err != nil {
		// A failed query may succeed after the environment is repaired.
		toolchainQueries.CompareAndDelete(key, query)
		return nil, query.err
	}
	return copyToolchain(query.toolchain), nil
}

func copyToolchain(toolchain map[string]string) map[string]string {
	copied := make(map[string]string, len(toolchain))
	for key, value := range toolchain {
		copied[key] = value
	}
	return copied
}
