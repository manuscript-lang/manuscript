package msruntime

import (
	"os"
	"path/filepath"
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
		if Profile(paths[0], paths[1], paths[2], func() int { called = true; return 0 }) != 70 || called || profiling.Load() {
			t.Fatal("setup error ran the callback or leaked state")
		}
	}
}
