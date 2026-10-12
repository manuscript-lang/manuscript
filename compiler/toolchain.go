package compiler

import (
	"fmt"
	support "github.com/manuscript-lang/manuscript"
	"os"
	"os/exec"
	"strings"
)

// goCommand keeps toolchain discovery and environment identical for pins and builds.
func goCommand(arguments ...string) (*exec.Cmd, error) {
	tool := os.Getenv("MANUSCRIPT_GO")
	settings := map[string]string{"GOTOOLCHAIN": "local", "CGO_ENABLED": "0", "GOENV": "off"}
	if tool == "" {
		if len(support.GoToolchainArchive) != 0 {
			root, err := bundledGoRoot()
			if err != nil {
				return nil, fmt.Errorf("prepare bundled toolchain: %w", err)
			}
			tool = goExecutable(root)
			settings["GOROOT"] = root
		} else {
			// Preserve direct go build and library embedding for developers.
			var err error
			tool, err = exec.LookPath("go")
			if err != nil {
				return nil, fmt.Errorf("this developer binary has no bundled toolchain; use a Manuscript release binary, run make build, or set MANUSCRIPT_GO: %w", err)
			}
		}
	}
	command := exec.Command(tool, arguments...)
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if _, replaced := settings[strings.ToUpper(key)]; !replaced {
			command.Env = append(command.Env, entry)
		}
	}
	for key, value := range settings {
		command.Env = append(command.Env, key+"="+value)
	}
	return command, nil
}
