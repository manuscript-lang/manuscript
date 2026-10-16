//go:build !unix

package hostos

import "os/exec"

// SetProcessGroup reports false: this host has no process groups to set.
func SetProcessGroup(*exec.Cmd) bool { return false }
