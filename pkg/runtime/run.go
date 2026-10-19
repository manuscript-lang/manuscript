package msruntime

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

// Test is one test block of the generated program.
type Test struct {
	Name    string
	Run     func(*Execution) Result[Unit, Error]
	Fixture *TestFixture
}

// Exit statuses of RunMain.
const (
	exitFault     = 70  // a fault, or cancellation without a signal
	exitInterrupt = 130 // SIGINT
	exitTerminate = 143 // SIGTERM
	maxMainExit   = 125 // 126 and above are reserved by shells
)

// RunMain runs the program's main function and returns its exit status. It
// cancels the root execution on SIGINT/SIGTERM (exit 130/143), reports faults
// on standard error (exit 70), waits for every joined operation, runs the
// host shutdown hook.
func RunMain(main func(*Execution) int, args []string) (exit int) {
	exit = exitFault
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	watch := watchStops(cancel)
	defer watch.stop()
	cancelledExit := func() int {
		switch watch.received() {
		case nil:
			return exitFault
		case os.Interrupt:
			return exitInterrupt
		}
		return exitTerminate
	}
	execution := rootExecution(ctx, args)
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(cancelled); ok {
				exit = cancelledExit()
			} else {
				fmt.Fprintln(os.Stderr, r)
				exit = exitFault
			}
		} else if ctx.Err() != nil {
			exit = cancelledExit()
		}
	}()
	// Host roots remain available until main and every joined operation finish.
	if hostShutdown != nil {
		defer Cleanup(execution, hostShutdown)
	}
	defer terminalRestoreAll()
	value := main(execution)
	CheckCancelled(execution)
	if value < 0 || value > maxMainExit {
		Raise("main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)")
	}
	return int(value)
}

// cleanupGrace is how long cleanup may run after the first stop request
// before the host escalates (see the contributor runtime contracts, "Host
// escalation"). Tests replace it.
var cleanupGrace = 30 * time.Second

// escalateExit ends the process when cleanup cannot finish. Tests replace it.
var escalateExit = os.Exit

// stopWatch cancels a run on its first SIGINT or SIGTERM and escalates when
// cleanup does not finish: a second stop request, or the grace period ending,
// writes a diagnostic and exits 70 without running further cleanup.
type stopWatch struct {
	mu     sync.Mutex
	first  os.Signal
	done   chan struct{}
	exited chan struct{}
	finish func()
}

func watchStops(cancel context.CancelFunc) *stopWatch {
	signals := make(chan os.Signal, 2)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	w := &stopWatch{done: make(chan struct{}), exited: make(chan struct{})}
	w.finish = func() { signal.Stop(signals) }
	go func() {
		defer close(w.exited)
		var grace <-chan time.Time
		for {
			select {
			case s := <-signals:
				w.mu.Lock()
				first := w.first == nil
				if first {
					w.first = s
				}
				w.mu.Unlock()
				if !first {
					escalate("a second stop request arrived before cleanup finished")
					return
				}
				cancel()
				timer := time.NewTimer(cleanupGrace)
				defer timer.Stop()
				grace = timer.C
			case <-grace:
				escalate(fmt.Sprintf("cleanup did not finish within %s of the stop request", cleanupGrace))
				return
			case <-w.done:
				return
			}
		}
	}()
	return w
}

// received returns the first stop signal, or nil when none arrived.
func (w *stopWatch) received() os.Signal {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.first
}

// stop ends the watch and restores the default signal behavior.
func (w *stopWatch) stop() {
	close(w.done)
	w.finish()
	<-w.exited
}

// escalate reports incomplete cleanup and ends the process.
func escalate(reason string) {
	fmt.Fprintln(os.Stderr, "incomplete cleanup: "+reason)
	escalateExit(exitFault)
}
