//go:build !linux && !darwin && !windows

package hostos

import (
	"errors"
	"os"
	"time"
)

// ResizeSupported reports whether WatchResize can observe window changes.
const ResizeSupported = false

func WatchResize(*os.File, <-chan struct{}) <-chan struct{} { return nil }
func EnableANSI(*os.File) (func() error, error)             { return nil, errors.ErrUnsupported }

// TerminalSupported reports whether raw terminal control exists on this host.
const TerminalSupported = false

func IsTerminal(*os.File) bool                           { return false }
func TerminalSize(*os.File) (int, int, error)            { return 0, 0, errors.ErrUnsupported }
func MakeRaw(*os.File) (func() error, error)             { return nil, errors.ErrUnsupported }
func WaitReadable(*os.File, time.Duration) (bool, error) { return false, errors.ErrUnsupported }
