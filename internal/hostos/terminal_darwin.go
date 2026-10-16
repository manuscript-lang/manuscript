//go:build darwin

package hostos

import "golang.org/x/sys/unix"

const (
	termiosGet = unix.TIOCGETA
	termiosSet = unix.TIOCSETA
)
