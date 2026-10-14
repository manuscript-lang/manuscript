// bench-literal-source retains emitted large constant literals for native
// compiler/runtime comparisons. Native build commands run separately.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func main() {
	count := flag.Int("count", 16000, "number of scalar elements")
	output := flag.String("output", ".artifacts/literal-source", "output directory")
	flag.Parse()
	if *count < 1 {
		panic("count must be positive")
	}
	var source strings.Builder
	source.WriteString("fn values() -> List[Int]: return [")
	for i := 0; i < *count; i++ {
		if i != 0 {
			source.WriteByte(',')
		}
		source.WriteString(strconv.Itoa(i))
	}
	source.WriteString("]\nexport fn main() -> Int: return values().length() - " + strconv.Itoa(*count) + "\n")
	result := compiler.CompileSource("literal.ms", source.String(), compiler.Options{Entry: true})
	if !result.Success() {
		panic(fmt.Sprint(result.Diagnostics))
	}
	if err := os.MkdirAll(*output, 0755); err != nil {
		panic(err)
	}
	for name, data := range map[string]string{"literal.ms": source.String(), "program.go": result.Source} {
		if err := os.WriteFile(filepath.Join(*output, name), []byte(data), 0644); err != nil {
			panic(err)
		}
	}
	fmt.Println(result.Program.Symbol("literal.ms", "values").ID)
}
