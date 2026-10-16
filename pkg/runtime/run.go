package msruntime

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
)

// Test is one test block of the generated program.
type Test struct {
	Name    string
	Run     func(*Execution) Unit
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
// host shutdown hook, and flushes runtime diagnostics.
func RunMain(main func(*Execution) int, args []string) (exit int) {
	exit = exitFault
	defer FlushDiagnostics()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	signals, stop := notifySignals()
	defer stop()
	done := make(chan struct{})
	defer close(done)
	var mu sync.Mutex
	signalExit := 0
	go func() {
		select {
		case s := <-signals:
			mu.Lock()
			if s == os.Interrupt {
				signalExit = exitInterrupt
			} else {
				signalExit = exitTerminate
			}
			mu.Unlock()
			cancel()
		case <-done:
		}
	}()
	cancelledExit := func() int {
		mu.Lock()
		defer mu.Unlock()
		if signalExit == 0 {
			return exitFault
		}
		return signalExit
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
	defer FinishExecution(execution)
	defer terminalRestoreAll()
	value := main(execution)
	CheckCancelled(execution)
	if value < 0 || value > maxMainExit {
		Raise("main exit code must be between 0 and 125; return 0 for success or a small positive Int for failure (126 and above are reserved by shells)")
	}
	return int(value)
}

// notifySignals delivers SIGINT and SIGTERM until stop is called.
func notifySignals() (<-chan os.Signal, func()) {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	return signals, func() { signal.Stop(signals) }
}
