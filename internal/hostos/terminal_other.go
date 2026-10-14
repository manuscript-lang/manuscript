//go:build !linux && !darwin

package hostos

import (
	"errors"
	"os"
	"time"
)

// ResizeSignal is nil where resize notification is unavailable.
var ResizeSignal os.Signal

// TerminalSupported reports whether raw terminal control exists on this host.
const TerminalSupported = false

func IsTerminal(*os.File) bool                           { return false }
func TerminalSize(*os.File) (int, int, error)            { return 0, 0, errors.ErrUnsupported }
func MakeRaw(*os.File) (func() error, error)             { return nil, errors.ErrUnsupported }
func WaitReadable(*os.File, time.Duration) (bool, error) { return false, errors.ErrUnsupported }
