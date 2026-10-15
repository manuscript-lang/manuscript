package msruntime

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// HostRoots are the program's capabilities to the host: standard streams,
// arguments, environment, and service handles. They are private to one CLI run
// or test; derived executions share them, so importing an accessor never
// creates a second service instance.
type HostRoots struct {
	once sync.Once
	err  error

	// Arguments is the program's argument list; Environment is the snapshot of
	// the process environment taken when the roots were initialized.
	Arguments   *List[string]
	Environment *Map[string, string]

	Stdin  ReadStream
	Stdout WriteStream
	Stderr WriteStream

	Files      Files
	Filesystem FileSystem
	Commands   Commands
	Control    ProcessControl
	Clock      Clock
	WallClock  WallClock
	Entropy    Entropy
	System     System
	Terminal   Terminal

	// Network is installed by the network module; it is nil until then.
	Network Network

	arguments []string
}

func init() {
	// RunMain and RunTests hand the program arguments to the host before main
	// runs. A startup failure (non-UTF-8 arguments or environment) is reported
	// by the first accessor that needs the roots.
	hostArguments = func(ctx *Execution, args []string) {
		if ctx.State.Host == nil {
			ctx.State.Host = &HostRoots{}
		}
		ctx.State.Host.Initialize(args)
	}
	hostShutdown = func(ctx *Execution) { ctx.State.Host.Shutdown(ctx) }
}

// NewHostRoots returns uninitialized roots for a run with arguments.
func NewHostRoots(arguments []string) *HostRoots { return &HostRoots{arguments: arguments} }

// Initialize creates the root services once. Later calls return the first
// call's outcome. args are the program arguments; nil keeps those given to
// NewHostRoots.
func (h *HostRoots) Initialize(args []string) error {
	h.once.Do(func() {
		if args != nil {
			h.arguments = args
		}
		h.err = h.build()
	})
	return h.err
}

func (h *HostRoots) build() error {
	values := make([]string, len(h.arguments))
	for i, a := range h.arguments {
		if !utf8.ValidString(a) {
			return fmt.Errorf("process arguments are not valid UTF-8")
		}
		values[i] = a
	}
	environment := NewMap[string, string]()
	for _, entry := range os.Environ() {
		if !utf8.ValidString(entry) {
			return fmt.Errorf("process environment is not valid UTF-8")
		}
		if name, value, ok := strings.Cut(entry, "="); ok {
			environment.Put(name, value)
		}
	}
	h.Arguments = NewList(values...)
	h.Environment = environment
	h.Filesystem = &osFileSystem{}
	h.Control = osProcessControl{}
	h.Entropy = osEntropy{}
	h.WallClock = osWallClock{}
	h.System = &osSystem{}
	h.Terminal = osTerminal{}
	h.Stdin = newHostStream(os.Stdin, false)
	h.Stdout = newHostStream(os.Stdout, false)
	h.Stderr = newHostStream(os.Stderr, false)
	h.Files = &osFiles{}
	h.Commands = osCommands{}
	h.Clock = &osClock{domain: &ClockDomain{}, start: time.Now()}
	return nil
}

// Shutdown releases the standard streams and the network service after main
// and every joined operation have finished. A fault while closing is
// reported to the caller as a Fault panic like any other cleanup fault.
func (h *HostRoots) Shutdown(ctx *Execution) {
	if h == nil || h.Initialize(nil) != nil {
		return
	}
	ctx = Shield(ctx)
	type closer interface{ Close(*Execution) Unit }
	var failures []any
	closeOne := func(c closer) {
		defer func() {
			if r := recover(); r != nil {
				failures = append(failures, r)
			}
		}()
		c.Close(ctx)
	}
	closeOne(h.Stdin)
	closeOne(h.Stdout)
	closeOne(h.Stderr)
	if h.Network != nil {
		if c, ok := h.Network.(closer); ok {
			closeOne(c)
		}
	}
	if len(failures) > 0 {
		panic(failures[0])
	}
}

// hostRoots returns the initialized roots of ctx.
func hostRoots(ctx *Execution) *HostRoots {
	if ctx == nil || ctx.State == nil || ctx.State.Host == nil {
		Raise("host services are unavailable in this execution")
	}
	if err := ctx.State.Host.Initialize(nil); err != nil {
		Raise(err.Error())
	}
	return ctx.State.Host
}

// Cli_Arguments is the cli.arguments root accessor.
func Cli_Arguments(ctx *Execution) *List[string] { return hostRoots(ctx).Arguments }

// Cli_Environment is the cli.environment root accessor: a snapshot taken at
// startup.
func Cli_Environment(ctx *Execution) *Map[string, string] { return hostRoots(ctx).Environment }

// Io_Stdin is the io.stdin root accessor.
func Io_Stdin(ctx *Execution) ReadStream { return hostRoots(ctx).Stdin }

// Io_Stdout is the io.stdout root accessor.
func Io_Stdout(ctx *Execution) WriteStream { return hostRoots(ctx).Stdout }

// Io_Stderr is the io.stderr root accessor.
func Io_Stderr(ctx *Execution) WriteStream { return hostRoots(ctx).Stderr }

// Io_Files is the io.files root accessor.
func Io_Files(ctx *Execution) Files { return hostRoots(ctx).Files }

// Fs_Filesystem is the fs.filesystem root accessor.
func Fs_Filesystem(ctx *Execution) FileSystem { return hostRoots(ctx).Filesystem }

// Process_Commands is the process.commands root accessor.
func Process_Commands(ctx *Execution) Commands { return hostRoots(ctx).Commands }

// Process_Control is the process.control root accessor.
func Process_Control(ctx *Execution) ProcessControl { return hostRoots(ctx).Control }

// Time_Clock is the time.clock root accessor.
func Time_Clock(ctx *Execution) Clock { return hostRoots(ctx).Clock }

// Time_WallClock is the time.wall_clock root accessor.
func Time_WallClock(ctx *Execution) WallClock { return hostRoots(ctx).WallClock }

// System_System is the system.system root accessor.
func System_System(ctx *Execution) System { return hostRoots(ctx).System }

// Terminal_Terminal is the terminal.terminal root accessor.
func Terminal_Terminal(ctx *Execution) Terminal { return hostRoots(ctx).Terminal }

// osWallClock reads the host's calendar time.
type osWallClock struct{}

var _ WallClock = osWallClock{}

func (osWallClock) Now(*Execution) Timestamp { return timestampOf(time.Now()) }

// osClock reads a monotonic clock whose instants carry its domain.
type osClock struct {
	domain *ClockDomain
	start  time.Time
}

var _ Clock = (*osClock)(nil)

func (c *osClock) Now(*Execution) Instant {
	return Instant{Domain: c.domain, Tick: int64(time.Since(c.start))}
}

// Shared host helpers.

var errInvalidInput = errors.New("invalid filesystem operation")
var errLimit = errors.New("limit exceeded")
var errEncoding = errors.New("name is not UTF-8")

// hostPath resolves s against directory, or the live working directory when
// directory is empty. An empty or NUL-containing path is invalid: an empty path
// would resolve to the working directory itself.
func hostPath(directory, s string) (string, bool) {
	if s == "" || strings.ContainsRune(s, 0) {
		return "", false
	}
	if filepath.IsAbs(s) {
		return s, true
	}
	if directory == "" {
		workingDirectoryMu.Lock()
		defer workingDirectoryMu.Unlock()
		var err error
		directory, err = os.Getwd()
		if err != nil {
			return "", false
		}
	}
	return filepath.Join(directory, s), true
}

var workingDirectoryMu sync.Mutex

// interruptFunc runs interrupt when ctx is cancelled. The returned stop
// disarms it and, when it already started, waits for it to finish.
func interruptFunc(ctx *Execution, interrupt func()) func() {
	done := make(chan struct{})
	stop := context.AfterFunc(ctx.Context, func() { defer close(done); interrupt() })
	return func() {
		if !stop() {
			<-done
		}
	}
}

// interruptDeadline expires an I/O deadline on cancellation; the returned stop
// also clears the deadline.
func interruptDeadline(ctx *Execution, deadline func(time.Time) error) func() {
	stop := interruptFunc(ctx, func() { deadline(time.Now()) })
	return func() {
		stop()
		deadline(time.Time{})
	}
}

// optionLimit resolves an optional limit: none selects fallback, a negative
// value is invalid.
func optionLimit(v Option[int64], fallback int64) (int64, bool) {
	if !v.Some {
		return fallback, true
	}
	return v.Val, v.Val >= 0
}

const unlimited = int64(^uint64(0) >> 1)
