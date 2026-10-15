//go:build unix

package mcp

import (
	"os/exec"
	"syscall"
	"time"
)

// configureGroup lets a timeout stop the whole process tree, including a native child.
func configureGroup(command *exec.Cmd) {
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	command.Cancel = func() error { return syscall.Kill(-command.Process.Pid, syscall.SIGKILL) }
	command.WaitDelay = 2 * time.Second
}
