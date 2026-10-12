package checker_test

import (
	"github.com/manuscript-lang/manuscript/checker"
	"github.com/manuscript-lang/manuscript/parser"
	"github.com/manuscript-lang/manuscript/syntax"
	"os"
	"path/filepath"
	"testing"
)

func TestAcceptedDesignFixtures(t *testing.T) {
	files, _ := filepath.Glob("../tests/e2e/testdata/accept/*.ms")
	for _, file := range files {
		t.Run(filepath.Base(file), func(t *testing.T) {
			source, err := os.ReadFile(file)
			if err != nil {
				t.Fatal(err)
			}
			m, err := parser.Parse(file, string(source))
			if err != nil {
				t.Fatal(err)
			}
			p := checker.Check([]*syntax.Module{m}, nil)
			for _, d := range p.Diagnostics {
				t.Error(d)
			}
		})
	}
}

func TestOmittedLabelPreservesSourceAST(t *testing.T) {
	source := "fn identity[T](value: T) -> T:\n    return value\nfn call() -> Int:\n    return identity(3)\n"
	module, err := parser.Parse("argument.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	call := module.Declarations[1].Body[0].Value
	for range 2 {
		program := checker.Check([]*syntax.Module{module}, nil)
		if len(program.Diagnostics) != 0 {
			t.Fatal(program.Diagnostics)
		}
		if call.Args[0].Name != "" {
			t.Fatal("checking changed the source argument label")
		}
		arguments := program.Expressions[call].Arguments
		if len(arguments) != 1 || arguments[0].Name != "value" || arguments[0].Value != call.Args[0].Value || arguments[0].Pos != call.Args[0].Pos {
			t.Fatal("incorrect checked argument mapping", arguments)
		}
	}
}
