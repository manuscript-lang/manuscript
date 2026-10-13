// Numeric-width controls measure Go storage, not an implemented language migration.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"reflect"
	"runtime"
	"strings"
	"time"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

type record32 struct {
	Integer int32
	Float   float32
	Flag    bool
}
type record64 struct {
	Integer int64
	Float   float64
	Flag    bool
}
type aligned32 struct {
	Name    string
	Integer int32
	Float   float32
}
type aligned64 struct {
	Name    string
	Integer int64
	Float   float64
}

var retained any
var checksum float64

func main() {
	kind := flag.String("case", "layout", "layout, boxed-int32/64, boxed-float32/64, typed-int32/64, typed-float32/64, boxed-record32/64, typed-record32/64")
	n := flag.Int("n", 1000000, "elements; use separate processes for RSS comparisons")
	flag.Parse()
	if *kind == "layout" {
		values := []any{int32(0), int64(0), float32(0), float64(0), (*any)(nil), []any{}, []int32{}, []int64{}, rt.List{}, rt.Record{}, rt.Alternative{}, record32{}, record64{}, aligned32{}, aligned64{}}
		for _, value := range values {
			t := reflect.TypeOf(value)
			fmt.Printf("%s size=%d align=%d\n", t, t.Size(), t.Align())
		}
		t := reflect.TypeOf((*any)(nil)).Elem()
		fmt.Printf("interface slot size=%d align=%d\n", t.Size(), t.Align())
		return
	}
	runtime.GC()
	var before, built, after runtime.MemStats
	runtime.ReadMemStats(&before)
	start := time.Now()
	// Values stay within signed32; checksums intentionally use an explicit wide host accumulator.
	switch *kind {
	case "boxed-int32":
		x := make([]any, *n)
		for i := range x {
			x[i] = int32(i%100003 + 257)
		}
		retained = x
	case "boxed-int64":
		x := make([]any, *n)
		for i := range x {
			x[i] = int64(i%100003 + 257)
		}
		retained = x
	case "boxed-float32":
		x := make([]any, *n)
		for i := range x {
			x[i] = float32(i%100003+257) / 3
		}
		retained = x
	case "boxed-float64":
		x := make([]any, *n)
		for i := range x {
			x[i] = float64(i%100003+257) / 3
		}
		retained = x
	case "typed-int32":
		x := make([]int32, *n)
		for i := range x {
			x[i] = int32(i%100003 + 257)
		}
		retained = x
	case "typed-int64":
		x := make([]int64, *n)
		for i := range x {
			x[i] = int64(i%100003 + 257)
		}
		retained = x
	case "typed-float32":
		x := make([]float32, *n)
		for i := range x {
			x[i] = float32(i%100003+257) / 3
		}
		retained = x
	case "typed-float64":
		x := make([]float64, *n)
		for i := range x {
			x[i] = float64(i%100003+257) / 3
		}
		retained = x
	case "boxed-record32", "boxed-record64":
		x := make([]rt.Value, *n)
		for i := range x {
			if *kind == "boxed-record64" {
				x[i] = rt.Record{Type: "WidthControl", Fields: map[string]rt.Value{"integer": int64(i%100003 + 257), "float": float64(i%100003+257) / 3, "flag": true}}
			} else {
				x[i] = rt.Record{Type: "WidthControl", Fields: map[string]rt.Value{"integer": int32(i%100003 + 257), "float": float32(i%100003+257) / 3, "flag": true}}
			}
		}
		retained = x
	case "typed-record32":
		x := make([]record32, *n)
		for i := range x {
			x[i] = record32{int32(i%100003 + 257), float32(i%100003+257) / 3, true}
		}
		retained = x
	case "typed-record64":
		x := make([]record64, *n)
		for i := range x {
			x[i] = record64{int64(i%100003 + 257), float64(i%100003+257) / 3, true}
		}
		retained = x
	default:
		fmt.Fprintln(os.Stderr, "unknown case", *kind)
		os.Exit(2)
	}
	construction := time.Since(start)
	runtime.ReadMemStats(&built)
	runtime.GC()
	runtime.ReadMemStats(&after)
	start = time.Now()
	for pass := 0; pass < 10; pass++ {
		var sum float64
		switch x := retained.(type) {
		case []any:
			for _, value := range x {
				switch v := value.(type) {
				case int32:
					sum += float64(v)
				case int64:
					sum += float64(v)
				case float32:
					sum += float64(v)
				case float64:
					sum += v
				case rt.Record:
					switch integer := v.Fields["integer"].(type) {
					case int32:
						sum += float64(integer)
					case int64:
						sum += float64(integer)
					}
				}
			}
		case []int32:
			for _, v := range x {
				sum += float64(v)
			}
		case []int64:
			for _, v := range x {
				sum += float64(v)
			}
		case []float32:
			for _, v := range x {
				sum += float64(v)
			}
		case []float64:
			for _, v := range x {
				sum += v
			}
		case []record32:
			for _, v := range x {
				sum += float64(v.Integer)
			}
		case []record64:
			for _, v := range x {
				sum += float64(v.Integer)
			}
		}
		checksum = sum
	}
	traversal := time.Since(start)
	status, _ := os.ReadFile("/proc/self/status")
	var rss []string
	for _, line := range strings.Split(string(status), "\n") {
		if strings.HasPrefix(line, "VmRSS:") || strings.HasPrefix(line, "VmHWM:") {
			rss = append(rss, line)
		}
	}
	result := map[string]any{"case": *kind, "n": *n, "go": runtime.Version(), "os": runtime.GOOS, "arch": runtime.GOARCH, "retained_heap_bytes": int64(after.HeapAlloc) - int64(before.HeapAlloc), "allocated_bytes": built.TotalAlloc - before.TotalAlloc, "allocations": built.Mallocs - before.Mallocs, "construction_ns": construction.Nanoseconds(), "traversal_10_pass_ns": traversal.Nanoseconds(), "rss": rss, "checksum": checksum}
	_ = json.NewEncoder(os.Stdout).Encode(result)
	runtime.KeepAlive(retained)
}
