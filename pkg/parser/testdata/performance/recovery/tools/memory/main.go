package main

import (
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

func main() {
	size, err := strconv.Atoi(os.Args[2])
	if err != nil {
		panic(err)
	}
	var source strings.Builder
	source.WriteString("fn broken(\nfn later(\n")
	for i := range size {
		fmt.Fprintf(&source, "value%d: Int,\n", i)
	}
	if os.Args[1] == "valid" {
		source.WriteString(") Int:\n    return 1\n")
	}
	text := source.String()
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	module, issues := parser.ParsePartial("memory.ms", text)
	runtime.ReadMemStats(&after)
	fmt.Printf("kind=%s size=%d declarations=%d issues=%d total_alloc_delta_bytes=%d mallocs_delta=%d heap_inuse_bytes=%d\n", os.Args[1], size, len(module.Declarations), len(issues), after.TotalAlloc-before.TotalAlloc, after.Mallocs-before.Mallocs, after.HeapInuse)
	runtime.KeepAlive(module)
	runtime.KeepAlive(issues)
}
