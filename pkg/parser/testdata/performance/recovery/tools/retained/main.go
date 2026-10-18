package main

import (
	"fmt"
	"runtime"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/parser"
)

var names []string

func main() {
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	for range 16 {
		// Each original CRLF recovery chunk owns its own normalized buffer.
		// Retaining the first function's name must not pin the later comment.
		source := "# prefix\r\nfn tiny(\r\na: Int,\r\n) Int:\r\n    return 1\r\nlet first = 1\r\n#" + strings.Repeat("x", 1<<20) + "\r\nlet second = 2\r\nfn broken(\r\n"
		module, issues := parser.ParsePartial("retained.ms", source)
		if len(module.Declarations) != 3 || len(issues) != 1 {
			panic("unexpected recovery result")
		}
		names = append(names, module.Declarations[0].Name)
	}
	runtime.GC()
	runtime.ReadMemStats(&after)
	fmt.Printf("retained_heap_delta_bytes=%d\n", int64(after.HeapAlloc)-int64(before.HeapAlloc))
	runtime.KeepAlive(names)
}
