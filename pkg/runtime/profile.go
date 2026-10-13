package msruntime

import (
	"context"
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
		sourceProfiling.Store(false)
		cpuProfiling.Store(false)
		traceProfiling.Store(false)
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
	cpuProfiling.Store(cpuStarted)
	traceProfiling.Store(traceStarted)
	sourceProfiling.Store(cpuStarted || traceStarted)
	ran = true
	return run()
}

// Source profiling is opt-in. Normal calls take one inexpensive atomic branch.
var sourceProfiling atomic.Bool
var profiling, cpuProfiling, traceProfiling atomic.Bool

// Select the profiling adapter before constructing a closure that its collector
// may retain. This keeps the ordinary guard/body path allocation-free. The
// adapter runs attribution inside the same guard, never through another wrapper.
func SourceCallNeedsProfile(ctx *Execution) bool {
	if !sourceProfiling.Load() || ctx == nil || ctx.Context == nil {
		return false
	}
	active, _ := ctx.Context.Value(sourceProfileKey{}).(bool)
	return !active
}

func ProfileSourceCall[T any](ctx *Execution, result, position string, body func(*Execution) T) T {
	return SourceCall(ctx, result, func(ctx *Execution) T { return profileSource(ctx, position, body) })
}

// A source boundary follows context inheritance, including cancellation
// shielding, but a work operation starts a fresh boundary. Nested source calls
// use Go's sampled stacks rather than allocating labels and regions per call.
type sourceProfileKey struct{}

func profileSource[T any](ctx *Execution, position string, body func(*Execution) T) (value T) {
	if ctx == nil || ctx.Context == nil {
		return body(ctx)
	}
	if active, _ := ctx.Context.Value(sourceProfileKey{}).(bool); active {
		return body(ctx)
	}
	run := func(labeled context.Context) {
		boundary := context.WithValue(labeled, sourceProfileKey{}, true)
		if traceProfiling.Load() {
			region := trace.StartRegion(boundary, "source:"+position)
			defer region.End()
		}
		// Attribution stays on the same execution/goroutine. Inherit creates
		// fresh call accounting for work; profiling must keep that state.
		execution := *ctx
		execution.Context = boundary
		value = body(&execution)
	}
	if cpuProfiling.Load() {
		pprof.Do(ctx.Context, pprof.Labels("ms.source", position), run)
	} else {
		run(ctx.Context)
	}
	return value
}
func profileWork(ctx *Execution, kind, id string, body func(*Execution) Value) (value Value) {
	if !sourceProfiling.Load() || ctx == nil || ctx.Context == nil {
		return body(ctx)
	}
	taskContext := context.WithValue(ctx.Context, sourceProfileKey{}, false)
	if traceProfiling.Load() {
		var task *trace.Task
		taskContext, task = trace.NewTask(taskContext, kind)
		defer task.End()
		trace.Log(taskContext, "ms.operation", id)
	}
	run := func(labeled context.Context) {
		execution := *ctx
		execution.Context = labeled
		value = body(&execution)
	}
	if cpuProfiling.Load() {
		pprof.Do(taskContext, pprof.Labels("ms.work", kind, "ms.operation", id), run)
	} else {
		run(taskContext)
	}
	return value
}
func profileRegion(ctx *Execution, name string) func() {
	if !traceProfiling.Load() || ctx == nil || ctx.Context == nil {
		return func() {}
	}
	region := trace.StartRegion(ctx.Context, name)
	return region.End
}
