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
