package compiler

import (
	"strings"
	"testing"
)

func TestSourceStandardModulesAreCheckedAndReachable(t *testing.T) {
	for _, name := range []string{"yaml", "toml"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			source := "import parse from \"@std/" + name + ".ms\"\nfn check() -> Unit:\n    let decoded = parse(text: \"a: 1\")\n"
			for range 2 {
				result := CompileSource("application.ms", source, Options{})
				if !result.Success() {
					t.Fatal(result.Diagnostics)
				}
				if len(result.Program.Modules) != 2 || result.Program.Modules[0].File != "@std/"+name+".ms" {
					t.Fatal("source standard module not included", result.Program.Modules)
				}
				if result.Program.Symbol("application.ms", "parse").Native != "" {
					t.Fatal("source parser lowered as native dispatch")
				}
				other := "toml"
				if name == other {
					other = "yaml"
				}
				if strings.Contains(result.Source, "@std/"+other+".ms") {
					t.Fatal("unreachable standard module was emitted")
				}
			}
			for _, imported := range []string{"Reader", "Context", "List", "Int", "Optional", "Result", "Error"} {
				result := CompileSource("private.ms", "import "+imported+" from \"@std/"+name+".ms\"\n", Options{AnalyzeOnly: true})
				if result.Success() {
					t.Fatal("standard source reexported private or imported symbol", imported)
				}
			}
		})
	}
	plain := CompileSource("plain.ms", "fn value() -> Int: return 1\n", Options{})
	if !plain.Success() || len(plain.Program.Modules) != 1 {
		t.Fatal("unimported standard implementations entered the program", plain.Diagnostics)
	}
}
