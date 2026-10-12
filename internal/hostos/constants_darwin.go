//go:build darwin

package hostos

import "golang.org/x/sys/unix"

func platformConstants() map[string]int64 {
	return map[string]int64{
		"SIGINFO": int64(unix.SIGINFO), "SIGEMT": int64(unix.SIGEMT),
		"RTLD_LAZY": 1, "RTLD_NOW": 2, "RTLD_GLOBAL": 8, "RTLD_LOCAL": 4,
	}
}

func platformFileConstants() map[string]int64 { return map[string]int64{} }
