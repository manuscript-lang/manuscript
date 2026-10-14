package msruntime

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"runtime/pprof"
	"strings"
	"testing"
)

func TestProfiles(t *testing.T) {
	dir := t.TempDir()
	cpu := filepath.Join(dir, "cpu.pprof")
	heap := filepath.Join(dir, "heap.pprof")
	trace := filepath.Join(dir, "trace.out")
	if got := Profile(cpu, heap, trace, func() int { return 7 }); got != 7 {
		t.Fatal(got)
	}
	for _, p := range []string{cpu, heap, trace} {
		s, e := os.Stat(p)
		if e != nil || s.Size() == 0 {
			t.Fatalf("missing profile %s: %v", p, e)
		}
	}
	called := false
	if Profile(cpu, "", "", func() int { called = true; return 0 }) != 70 || called {
		t.Fatal("overwrote profile")
	}
	for _, paths := range [][3]string{{"", heap, ""}, {"", "", trace}} {
		if Profile(paths[0], paths[1], paths[2], func() int { called = true; return 0 }) != 70 || called || profiling.Load() || sourceProfiling.Load() {
			t.Fatal("setup error ran the callback or leaked state")
		}
	}
}

func TestSourceProfilesPreserveExecutionAndAttributeWork(t *testing.T) {
	root := RootExecution()
	site := "source.ms:12:4"
	observed := false
	fn := NewSourceFunction(nil, "Int", site, func(ctx *Execution, _ []Value) Value {
		label, ok := pprof.Label(ctx.Context, "ms.source")
		if !ok || label != site || ctx.Lifetime != root.Lifetime || ctx.Context.Done() != root.Context.Done() {
			t.Fatal("source attribution changed execution", label)
		}
		return profileWork(ctx, "task_group.operation", "7", func(child *Execution) Value {
			kind, _ := pprof.Label(child.Context, "ms.work")
			id, _ := pprof.Label(child.Context, "ms.operation")
			if kind != "task_group.operation" || id != "7" {
				t.Fatal(kind, id)
			}
			observed = true
			return int64(42)
		})
	})
	directory := t.TempDir()
	traceFile := filepath.Join(directory, "trace.out")
	if exit := Profile(filepath.Join(directory, "cpu.pprof"), "", traceFile, func() int {
		if Invoke(root, fn, nil) != int64(42) {
			t.Fatal("changed result")
		}
		return 0
	}); exit != 0 || !observed {
		t.Fatal(exit, observed)
	}
	if _, ok := pprof.Label(root.Context, "ms.source"); ok {
		t.Fatal("source labels leaked into caller")
	}
	data, err := os.ReadFile(traceFile)
	if err != nil || !bytes.Contains(data, []byte("source:"+site)) || !bytes.Contains(data, []byte("task_group.operation")) {
		t.Fatal("trace lacks source/work regions", err)
	}
}

func TestSourceProfileBoundaries(t *testing.T) {
	for _, mode := range []string{"none", "heap", "cpu", "trace", "both"} {
		t.Run(mode, func(t *testing.T) {
			dir := t.TempDir()
			var cpu, heap, traceFile string
			if mode == "cpu" || mode == "both" {
				cpu = filepath.Join(dir, "cpu.pprof")
			}
			if mode == "heap" {
				heap = filepath.Join(dir, "heap.pprof")
			}
			if mode == "trace" || mode == "both" {
				traceFile = filepath.Join(dir, "trace.out")
			}
			active := cpu != "" || traceFile != ""
			root := RootExecution()
			var boundary *Execution
			var nested Function
			nested = NewSourceFunction(nil, "Int", "nested.ms:2:1", func(ctx *Execution, args []Value) Value {
				// Even distinct nested sites and recursive calls reuse the entry
				// execution instead of allocating profiling state per call.
				if ctx != boundary {
					t.Fatal("nested call derived another execution")
				}
				if args[0].(int64) > 0 {
					return nested.Body(ctx, []Value{args[0].(int64) - 1})
				}
				return Return(int64(42))
			})
			operation := NewSourceFunction(nil, "Int", "work.ms:3:1", func(ctx *Execution, _ []Value) Value {
				label, ok := pprof.Label(ctx.Context, "ms.source")
				if cpu != "" && (!ok || label != "work.ms:3:1") {
					t.Fatal("work inherited the submitting source", label)
				}
				if ctx.Lifetime != root.Lifetime || ctx.Host != root.Host || ctx.Context.Done() != root.Context.Done() || ctx.calls != root.calls {
					t.Fatal("work profiling changed execution identity")
				}
				return int64(9)
			})
			entry := NewSourceFunction(nil, "Int", "entry.ms:1:1", func(ctx *Execution, _ []Value) Value {
				boundary = ctx
				label, ok := pprof.Label(ctx.Context, "ms.source")
				if cpu != "" && (!ok || label != "entry.ms:1:1") || cpu == "" && ok {
					t.Fatal("unexpected source CPU label", label)
				}
				if active == (ctx == root) {
					t.Fatal("unexpected entry derivation")
				}
				if ctx.calls != root.calls {
					t.Fatal("source profiling reset call accounting")
				}
				if nested.Body(ctx, []Value{int64(1000)}) != int64(42) {
					t.Fatal("source return changed")
				}
				if profileWork(ctx, "task_group.operation", "8", func(child *Execution) Value {
					return Invoke(child, operation, nil)
				}) != int64(9) {
					t.Fatal("work result changed")
				}
				if label, _ := pprof.Label(ctx.Context, "ms.source"); cpu != "" && label != "entry.ms:1:1" {
					t.Fatal("work label leaked into source caller")
				}
				return int64(0)
			})
			if exit := Profile(cpu, heap, traceFile, func() int { return int(Invoke(root, entry, nil).(int64)) }); exit != 0 {
				t.Fatal(exit)
			}
			if sourceProfiling.Load() || cpuProfiling.Load() || traceProfiling.Load() || profiling.Load() {
				t.Fatal("profiling state leaked after capture")
			}
			if _, ok := pprof.Label(root.Context, "ms.source"); ok {
				t.Fatal("source label leaked into root")
			}
			if traceFile != "" {
				data, err := os.ReadFile(traceFile)
				if err != nil || !bytes.Contains(data, []byte("source:entry.ms:1:1")) || !bytes.Contains(data, []byte("source:work.ms:3:1")) || bytes.Contains(data, []byte("source:nested.ms:2:1")) {
					t.Fatal("trace boundary attribution changed", err)
				}
			}
		})
	}
}

func TestProfileFailuresAndRepeatedRuns(t *testing.T) {
	for _, failure := range []string{"fault", "cancelled", "overlap"} {
		for repeat := 0; repeat < 2; repeat++ {
			dir := t.TempDir()
			root := RootExecution()
			ctx, cancel := context.WithCancel(root.Context)
			root.Context = ctx
			fn := NewSourceFunction(nil, "Int", "failure.ms:1:1", func(execution *Execution, _ []Value) Value {
				switch failure {
				case "fault":
					return Panic("profile fault")
				case "cancelled":
					cancel()
					CheckCancelled(execution)
				case "overlap":
					if Profile(filepath.Join(dir, "overlap.pprof"), "", "", func() int { t.Fatal("overlapping capture ran"); return 0 }) != 70 || !sourceProfiling.Load() {
						t.Fatal("overlapping capture disrupted active session")
					}
				}
				return int64(0)
			})
			got := recovered(func() {
				Profile(filepath.Join(dir, "cpu.pprof"), filepath.Join(dir, "heap.pprof"), filepath.Join(dir, "trace.out"), func() int {
					return int(Invoke(root, fn, nil).(int64))
				})
			})
			cancel()
			switch failure {
			case "fault":
				if fault, ok := got.(Fault); !ok || fault.Message != "profile fault" {
					t.Fatal("profiling changed fault", got)
				}
			case "cancelled":
				if _, ok := got.(cancelled); !ok {
					t.Fatal("profiling changed cancellation", got)
				}
			case "overlap":
				if got != nil {
					t.Fatal(got)
				}
			}
			if profiling.Load() || sourceProfiling.Load() || cpuProfiling.Load() || traceProfiling.Load() {
				t.Fatal("failed capture leaked profiling state")
			}
			for _, name := range []string{"cpu.pprof", "heap.pprof", "trace.out"} {
				info, err := os.Stat(filepath.Join(dir, name))
				if err != nil || info.Size() == 0 {
					t.Fatalf("capture did not flush %s: %v", name, err)
				}
			}
		}
	}
}

func TestNestedSourceProfilingDoesNotAllocate(t *testing.T) {
	inner := NewSourceFunction(nil, "Int", "inner.ms:2:1", func(_ *Execution, _ []Value) Value { return int64(0) })
	entry := NewSourceFunction(nil, "Int", "entry.ms:1:1", func(ctx *Execution, _ []Value) Value {
		if allocations := testing.AllocsPerRun(100, func() { inner.Body(ctx, nil) }); allocations != 0 {
			t.Fatalf("nested source profiling allocated %v objects per call", allocations)
		}
		return int64(0)
	})
	if exit := Profile(filepath.Join(t.TempDir(), "cpu.pprof"), "", "", func() int { return int(Invoke(RootExecution(), entry, nil).(int64)) }); exit != 0 {
		t.Fatal(exit)
	}
}

func TestProfilingPreservesCallDepthLimit(t *testing.T) {
	for _, mode := range []string{"cpu", "trace", "both"} {
		t.Run(mode, func(t *testing.T) {
			root := RootExecution()
			root.calls.depth = MaxCallDepth - 1
			root.calls.traceFull = true
			inner := NewSourceFunction(nil, "Int", "inner.ms:2:1", func(_ *Execution, _ []Value) Value {
				t.Fatal("profiled call crossed the source depth limit")
				return int64(0)
			})
			entry := NewSourceFunction(nil, "Int", "entry.ms:1:1", func(ctx *Execution, _ []Value) Value {
				if ctx.calls != root.calls || ctx.calls.depth != MaxCallDepth || !ctx.calls.traceFull {
					t.Fatal("attribution replaced call/fault accounting")
				}
				failure := recovered(func() { Invoke(ctx, inner, nil) })
				if fault, ok := failure.(Fault); !ok || !strings.Contains(fault.Message, "call depth limit exceeded") {
					t.Fatal("profiling changed depth-limit fault", failure)
				}
				return int64(0)
			})
			dir := t.TempDir()
			var cpu, traceFile string
			if mode != "trace" {
				cpu = filepath.Join(dir, "cpu.pprof")
			}
			if mode != "cpu" {
				traceFile = filepath.Join(dir, "trace.out")
			}
			if exit := Profile(cpu, "", traceFile, func() int { return int(Invoke(root, entry, nil).(int64)) }); exit != 0 || root.calls.depth != MaxCallDepth-1 {
				t.Fatal("profiled call did not restore depth", exit, root.calls.depth)
			}
		})
	}
}
