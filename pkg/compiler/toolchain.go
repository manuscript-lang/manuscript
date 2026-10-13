package compiler

import (
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"sync"
)

// goCommand keeps toolchain discovery and environment identical for pins and builds.
func goCommand(arguments ...string) (*exec.Cmd, error) {
	tool, environment, err := goToolchain()
	if err != nil {
		return nil, err
	}
	command := exec.Command(tool, arguments...)
	command.Env = environment
	return command, nil
}

func goToolchain() (string, []string, error) {
	root, err := bundledGoRoot()
	if err != nil {
		return "", nil, fmt.Errorf("prepare bundled toolchain: %w", err)
	}
	cache, err := userCacheRoot()
	if err != nil {
		return "", nil, err
	}
	settings := map[string]string{
		"GOROOT": root, "GOTOOLCHAIN": "local", "CGO_ENABLED": "0", "GOENV": "off",
		"GOOS": runtime.GOOS, "GOARCH": runtime.GOARCH, "GOFLAGS": "", "GOWORK": "off",
		"GO111MODULE": "on", "GOPROXY": "off", "GOSUMDB": "off", "GOTELEMETRY": "off",
		"GOCACHE":    filepath.Join(cache, "manuscript", "go-build"),
		"GOPATH":     filepath.Join(cache, "manuscript", "go"),
		"GOMODCACHE": filepath.Join(cache, "manuscript", "go", "pkg", "mod"),
	}
	var environment []string
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if key = strings.ToUpper(key); !strings.HasPrefix(key, "GO") && !strings.HasPrefix(key, "CGO_") {
			environment = append(environment, entry)
		}
	}
	for _, key := range slices.Sorted(maps.Keys(settings)) {
		environment = append(environment, key+"="+settings[key])
	}
	return goExecutable(root), environment, nil
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
