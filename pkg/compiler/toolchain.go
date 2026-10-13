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
				return "", nil, fmt.Errorf("no Go toolchain found: this developer binary has no bundled toolchain and go is not on PATH; install Go 1.25 or newer, set MANUSCRIPT_GO to a go executable, or use a Manuscript release binary: %w", err)
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
