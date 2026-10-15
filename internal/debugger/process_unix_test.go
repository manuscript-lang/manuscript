//go:build !windows

package debugger

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"golang.org/x/sys/unix"
)

func diagnosticPipeCapacity(*os.File) (int, error) { return 0, nil }

func processAlive(pid int) bool { return unix.Kill(pid, 0) == nil }

func nativeConsole(context.Context, context.CancelFunc) (func() error, error) {
	return nil, fmt.Errorf("native Windows console test requires Windows")
}

func checkClosedHistory(path string) error {
	if runtime.GOOS != "linux" {
		return nil
	}
	fds, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return err
	}
	for _, fd := range fds {
		name, _ := os.Readlink(filepath.Join("/proc/self/fd", fd.Name()))
		if name == path {
			return fmt.Errorf("terminal history file survived session return: %s", path)
		}
	}
	return nil
}
