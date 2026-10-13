package checker

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func TestPinnedSourceHelpersKeepPrivateCheckedSignatures(t *testing.T) {
	ensureStandard()
	for _, name := range []string{"same_list", "same_table"} {
		symbol := standardModules["@std/toml.ms"][name]
		if symbol == nil || symbol.Export || symbol.Native != "toml/"+name || len(symbol.Decl.Body) != 0 || len(symbol.Variables) != 1 {
			t.Fatalf("private native helper lost its pinned declaration: %#v", symbol)
		}
		if standardSourceFunctionBindings[symbol.Decl] != symbol.Native {
			t.Fatal("private helper binding is not attached to its exact declaration")
		}
		module, err := parser.Parse("caller.ms", "import "+name+" from \"@std/toml.ms\"\n")
		if err != nil {
			t.Fatal(err)
		}
		program := Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) == 0 {
			t.Fatal("private helper became importable")
		}
	}
}

func TestSourceNativeHelpersRequirePinnedModuleAndDeclaration(t *testing.T) {
	for _, file := range []string{"application.ms", "@std/toml.ms"} {
		for _, body := range []string{"", "\n    return true\n"} {
			source := "fn same_list[T](left: List[T], right: List[T]) -> Bool:" + body
			module, err := parser.Parse(file, source)
			if err != nil {
				t.Fatal(err)
			}
			program := Check([]*syntax.Module{module}, nil)
			if symbol := program.Symbol(file, "same_list"); symbol == nil || symbol.Native != "" {
				t.Fatalf("a user declaration acquired a native helper binding: %#v", symbol)
			}
			if body != "" {
				if len(program.Diagnostics) > 0 {
					t.Fatal(program.Diagnostics)
				}
			} else if len(program.Diagnostics) == 0 || !strings.Contains(program.Diagnostics[0].Message, "reachable fallthrough") {
				t.Fatalf("a user empty function bypassed body checking: %v", program.Diagnostics)
			}
		}
	}
}
