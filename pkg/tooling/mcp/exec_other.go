//go:build !unix

package mcp

import (
	"os/exec"
	"time"
)

func configureGroup(command *exec.Cmd) { command.WaitDelay = 2 * time.Second }
