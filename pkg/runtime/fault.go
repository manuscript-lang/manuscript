package msruntime

import "strings"

// Fault is a Manuscript fault: a programming error that unwinds the task.
type Fault struct {
	Message   string
	Secondary []string
	Frames    []string
	Truncated bool
}

func (f Fault) Error() string {
	message := f.Message
	if len(f.Frames) > 0 {
		message += "\n  at " + strings.Join(f.Frames, "\n  at ")
	}
	if f.Truncated {
		message += "\n  ... outer frames omitted"
	}
	for _, secondary := range f.Secondary {
		message += "\ncleanup fault: " + secondary
	}
	return message
}

// Raise raises a fault with message; it never returns.
// Keep stack capture on the cold path. Inlining it into small checked helpers
// otherwise prevents those helpers from inlining at their ordinary call sites.
//
//go:noinline
func Raise(message string) {
	frames, truncated := captureFrames()
	panic(Fault{Message: message, Frames: frames, Truncated: truncated})
}
