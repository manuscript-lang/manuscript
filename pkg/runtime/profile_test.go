package msruntime

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime/pprof"
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
	if exit := Profile("", "", traceFile, func() int {
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
