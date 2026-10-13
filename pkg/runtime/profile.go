package msruntime

import (
	"context"
	"fmt"
	"os"
	goruntime "runtime"
	"runtime/pprof"
	"runtime/trace"
	"sync"
	"sync/atomic"
)

// Profile runs an entry under explicitly requested local profiling. No network listener is opened.
func Profile(cpuPath, heapPath, tracePath string, run func() int) (exit int) {
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
		sourceTracing.Store(false)
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
	sourceTracing.Store(traceStarted)
	sourceProfiling.Store(cpuStarted || traceStarted)
	ran = true
	return run()
}

// Source profiling is opt-in. Normal calls take one inexpensive atomic branch.
var sourceProfiling atomic.Bool

// Execution tracing records an event and a stack walk for every region, which
// dominates call-heavy programs, so source regions are emitted only when a trace
// was explicitly requested.
var sourceTracing atomic.Bool

// Label sets are immutable and a program has few distinct call positions, so
// build each once instead of per call.
var sourceLabels sync.Map // position -> pprof.LabelSet

func sourceLabelSet(position string) pprof.LabelSet {
	if labels, ok := sourceLabels.Load(position); ok {
		return labels.(pprof.LabelSet)
	}
	labels := pprof.Labels("ms.source", position)
	sourceLabels.Store(position, labels)
	return labels
}

func profileSource(ctx *Execution, position string, args []Value, body func(*Execution, []Value) Value) (value Value) {
	if ctx == nil || ctx.Context == nil {
		return body(ctx, args)
	}
	pprof.Do(ctx.Context, sourceLabelSet(position), func(labeled context.Context) {
		if sourceTracing.Load() {
			region := trace.StartRegion(labeled, "source:"+position)
			defer region.End()
		}
		value = body(inherit(ctx, labeled), args)
	})
	return value
}
func profileWork(ctx *Execution, kind, id string, body func(*Execution) Value) (value Value) {
	if !sourceProfiling.Load() {
		return body(ctx)
	}
	taskContext, task := trace.NewTask(ctx.Context, kind)
	defer task.End()
	trace.Log(taskContext, "ms.operation", id)
	pprof.Do(taskContext, pprof.Labels("ms.work", kind, "ms.operation", id), func(labeled context.Context) { value = body(inherit(ctx, labeled)) })
	return value
}
func profileRegion(ctx *Execution, name string) func() {
	if !sourceProfiling.Load() || ctx == nil {
		return func() {}
	}
	region := trace.StartRegion(ctx.Context, name)
	return region.End
}
