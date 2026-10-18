package main

import (
	"fmt"
	"os"
	"runtime"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/lexer"
	"github.com/manuscript-lang/manuscript/pkg/parser"
)

var paths []string
var punctuation [][]lexer.Token

func retain(mode string) {
	for range 16 {
		source := "#" + strings.Repeat("x", 1<<20) + "\n"
		if mode == "path" {
			source += "import Thing from \"./tiny.ms\"\n"
			module, err := parser.Parse("retained.ms", source)
			if err != nil {
				panic(err)
			}
			paths = append(paths, module.Imports[0].Path)
		} else {
			tokens, err := lexer.Lex("retained.ms", source+"+\n")
			if err != nil {
				panic(err)
			}
			punctuation = append(punctuation, tokens)
		}
	}
}

func main() {
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	retain(os.Args[1])
	runtime.GC()
	runtime.ReadMemStats(&after)
	fmt.Printf("mode=%s retained_heap_delta_bytes=%d\n", os.Args[1], int64(after.HeapAlloc)-int64(before.HeapAlloc))
	runtime.KeepAlive(paths)
	runtime.KeepAlive(punctuation)
}
