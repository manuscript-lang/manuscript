package msruntime

import (
	"fmt"
	"os"
	goruntime "runtime"
	"runtime/pprof"
	"runtime/trace"
	"sync/atomic"
)

// Profile runs an entry under explicitly requested local profiling. No network listener is opened.
func Profile(cpuPath, heapPath, tracePath string, run func() int) (exit int) {
	if cpuPath == "" && heapPath == "" && tracePath == "" {
		return run()
	}
	// Go's profilers are process-wide. Reject overlap without changing the
	// active session's flags or stopping its collectors.
	if !profiling.CompareAndSwap(false, true) {
		fmt.Fprintln(os.Stderr, "profiling is already active; finish the current capture before starting another")
		return 70
	}
	defer profiling.Store(false)
	var cpu, traceFile, heap *os.File
	var err error
	files := []*os.File{}
	defer func() {
		for _, f := range files {
			_ = f.Close()
		}
	}()
	open := func(path string) (*os.File, error) {
		if path == "" {
			return nil, nil
		}
		f, e := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if e == nil {
			files = append(files, f)
		}
		return f, e
	}
	if cpu, err = open(cpuPath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 70
	}
	if heap, err = open(heapPath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 70
	}
	if traceFile, err = open(tracePath); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 70
	}
	cpuStarted, traceStarted, ran := false, false, false
	defer func() {
		if traceStarted {
			trace.Stop()
		}
		if cpuStarted {
			pprof.StopCPUProfile()
		}
		if ran && heap != nil {
			goruntime.GC()
			if err := pprof.WriteHeapProfile(heap); err != nil {
				fmt.Fprintln(os.Stderr, err)
				exit = 70
			}
		}
	}()

	if cpu != nil {
		if err = pprof.StartCPUProfile(cpu); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 70
		}
		cpuStarted = true
	}
	if traceFile != nil {
		if err = trace.Start(traceFile); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 70
		}
		traceStarted = true
	}
	ran = true
	return run()
}

var profiling atomic.Bool
