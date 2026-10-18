package checker

import (
	"sync"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

func checkText(t *testing.T, source string) *Program {
	t.Helper()
	module, err := parser.Parse("lazy.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	program := Check([]*syntax.Module{module}, nil)
	for _, d := range program.Diagnostics {
		t.Error(d)
	}
	return program
}

func TestBundledSourceModulesCheckOnFirstImport(t *testing.T) {
	ensureStandard()
	standardMu.Lock()
	standardDone = map[string]*standardResult{}
	standardMu.Unlock()
	checkText(t, "fn one() Int:\n    return 1\n")
	if len(standardDone) != 0 {
		t.Fatalf("program without bundled imports checked %d bundled modules", len(standardDone))
	}
	checkText(t, "import TomlValue from \"@std/toml.ms\"\nfn one() Int:\n    return 1\n")
	if standardDone["@std/toml.ms"] == nil || standardDone["@std/yaml.ms"] != nil {
		t.Fatalf("expected only toml checked, got %v", len(standardDone))
	}
}

func TestBundledSourceModulesCheckOnceConcurrently(t *testing.T) {
	ensureStandard()
	var group sync.WaitGroup
	for range 8 {
		group.Add(1)
		go func() {
			defer group.Done()
			checkText(t, "import TomlValue from \"@std/toml.ms\"\nimport YamlValue from \"@std/yaml.ms\"\nfn one() Int:\n    return 1\n")
		}()
	}
	group.Wait()
}
