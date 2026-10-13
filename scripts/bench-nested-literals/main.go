// bench-nested-literals measures checker work independently of parser limits.
// Build/run it with the checkout's pinned Go SDK. It constructs syntax nodes
// directly, preserving the parser's source nesting guard.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func main() {
	depths := flag.String("depths", "500,1000,2000,4000", "comma-separated AST depths")
	kinds := flag.String("kinds", "list,map", "comma-separated collection kinds")
	count := flag.Int("count", 3, "repetitions at each depth")
	flag.Parse()
	module, err := parser.Parse("nested.ms", "fn values() -> Unit:\n    let xs = 1\n")
	if err != nil {
		panic(err)
	}
	checker.Check([]*syntax.Module{module}, nil) // Warm pinned standard declarations.
	encoder := json.NewEncoder(os.Stdout)
	for _, kind := range strings.Split(*kinds, ",") {
		if kind != "list" && kind != "map" {
			panic("kind must be list or map")
		}
		for _, text := range strings.Split(*depths, ",") {
			depth, err := strconv.Atoi(text)
			if err != nil || depth < 0 {
				panic("invalid depth")
			}
			position := module.Declarations[0].Body[0].Pos
			value := &syntax.Expression{Kind: syntax.KindNumber, Text: "1", Pos: position}
			for range depth {
				elements := []*syntax.Expression{value}
				if kind == "map" {
					elements = []*syntax.Expression{{Kind: syntax.KindNumber, Text: "1", Pos: position}, value}
				}
				value = &syntax.Expression{Kind: kind, Elements: elements, Pos: position}
			}
			module.Declarations[0].Body[0].Value = value
			for sample := 0; sample < *count; sample++ {
				runtime.GC()
				var before, after runtime.MemStats
				runtime.ReadMemStats(&before)
				start := time.Now()
				program := checker.Check([]*syntax.Module{module}, nil)
				elapsed := time.Since(start)
				runtime.ReadMemStats(&after)
				row := struct {
					Kind               string `json:"kind"`
					Depth, Sample      int
					Seconds            float64
					Bytes, Allocations uint64
					Diagnostics        int
				}{
					Kind: kind, Depth: depth, Sample: sample, Seconds: elapsed.Seconds(), Bytes: after.TotalAlloc - before.TotalAlloc, Allocations: after.Mallocs - before.Mallocs, Diagnostics: len(program.Diagnostics),
				}
				if err := encoder.Encode(row); err != nil {
					panic(err)
				}
				if len(program.Diagnostics) != 0 {
					fmt.Fprintln(os.Stderr, program.Diagnostics)
					os.Exit(1)
				}
			}
		}
	}
}
