package compiler

import (
	"encoding/json"
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"maps"
	"os"
	"os/exec"
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
	tool := os.Getenv("MANUSCRIPT_GO")
	settings := map[string]string{"GOTOOLCHAIN": "local", "CGO_ENABLED": "0", "GOENV": "off"}
	if tool == "" {
		if len(support.GoToolchainArchive) != 0 {
			root, err := bundledGoRoot()
			if err != nil {
				return "", nil, fmt.Errorf("prepare bundled toolchain: %w", err)
			}
			tool = goExecutable(root)
			settings["GOROOT"] = root
		} else {
			// Preserve direct go build and library embedding for developers.
			var err error
			tool, err = exec.LookPath("go")
			if err != nil {
				return "", nil, fmt.Errorf("this developer binary has no bundled toolchain; use a Manuscript release binary, run make build, or set MANUSCRIPT_GO: %w", err)
			}
		}
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
	return tool, environment, nil
}

// Toolchain queries are remembered per tool and environment, so one process
// that pins and builds (or builds repeatedly) runs go env only once.
var toolchainQueries sync.Map

func queryToolchain() (map[string]string, error) {
	command, err := goCommand("env", "-json", "GOVERSION", "GOOS", "GOARCH", "CGO_ENABLED", "GOEXPERIMENT", "GOFLAGS", "GOAMD64", "GOARM", "GOARM64", "GOMIPS", "GOMIPS64", "GOPPC64", "GORISCV64", "GOWASM")
	if err != nil {
		return nil, err
	}
	key := command.Path + "\x00" + strings.Join(command.Env, "\x00")
	if cached, ok := toolchainQueries.Load(key); ok {
		return copyToolchain(cached.(map[string]string)), nil
	}
	data, err := command.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("read Go toolchain: %w: %s", err, data)
	}
	var toolchain map[string]string
	if err := json.Unmarshal(data, &toolchain); err != nil {
		return nil, err
	}
	toolchainQueries.Store(key, toolchain)
	return copyToolchain(toolchain), nil
}

func copyToolchain(toolchain map[string]string) map[string]string {
	copied := make(map[string]string, len(toolchain))
	for key, value := range toolchain {
		copied[key] = value
	}
	return copied
}
