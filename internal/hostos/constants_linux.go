//go:build linux

package hostos

import "golang.org/x/sys/unix"

func platformConstants() map[string]int64 {
	return map[string]int64{
		"SIGSTKFLT": int64(unix.SIGSTKFLT),
		"SIGPOLL":   int64(unix.SIGPOLL),
		"SIGPWR":    int64(unix.SIGPWR),
		"RTLD_LAZY": 1, "RTLD_NOW": 2, "RTLD_GLOBAL": 256, "RTLD_LOCAL": 0, "RTLD_DEEPBIND": 8,
	}
}

func platformFileConstants() map[string]int64 {
	return map[string]int64{"O_NOATIME": int64(unix.O_NOATIME),
		"O_DIRECT": int64(unix.O_DIRECT),
	}
}
