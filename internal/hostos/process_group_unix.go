//go:build unix

package hostos

import (
	"os/exec"
	"syscall"
)

// SetProcessGroup starts cmd in its own process group and reports whether the
// host supports one.
func SetProcessGroup(cmd *exec.Cmd) bool {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return true
}
