package compiler

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"runtime"
)

// ProfileCommand opens captured profiles using only the embedded SDK's viewers.
// This deliberately does not expose arbitrary go subcommands.
func ProfileCommand(tool string, arguments ...string) (*exec.Cmd, error) {
	if tool != "pprof" && tool != "trace" {
		return nil, fmt.Errorf("unsupported profile viewer %q", tool)
	}
	goTool, environment, err := goToolchain()
	if err != nil {
		return nil, err
	}
	name := tool
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	executable := filepath.Join(filepath.Dir(filepath.Dir(goTool)), "pkg", "tool", runtime.GOOS+"_"+runtime.GOARCH, name)
	command := exec.Command(executable, arguments...)
	command.Env = environment
	return command, nil
}
