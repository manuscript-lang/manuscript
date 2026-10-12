package parser

import (
	"strings"
	"testing"
)

func TestPartialParserPreservesPositionsAndStrictFailure(t *testing.T) {
	source := "# prefix\r\nfn good(input: Int) -> Int:\r\n    return input\r\nfn broken(\r\nfn later() -> Int:\r\n    return 2\r\n"
	if _, err := Parse("source.ms", source); err == nil {
		t.Fatal("strict parser accepted incomplete source")
	}
	module, issues := ParsePartial("source.ms", source)
	if len(issues) == 0 || len(module.Declarations) != 2 {
		t.Fatal(module, issues)
	}
	later := module.Declarations[1]
	if later.Pos.Line != 5 || later.Pos.Offset != strings.Index(source, "fn later") || later.Body[0].Value.Pos.Offset != strings.Index(source, "2\r\n") {
		t.Fatal(later)
	}
}

func FuzzParsePartial(f *testing.F) {
	for _, seed := range []string{"", "fn unfinished(\nfn valid() -> Int:\n    return 1\n", "type Box:\n    value: String\n", "# 😀\r\nfn read() -> Int:\r\n    return 2\r\n"} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, source string) {
		module, issues := ParsePartial("fuzz.ms", source)
		if module == nil || module.Source != source {
			t.Fatal("lost source")
		}
		for _, decl := range module.Declarations {
			if decl.Pos.Offset < 0 || decl.Pos.Offset > len(source) {
				t.Fatal("declaration outside source", decl.Pos)
			}
		}
		for _, issue := range issues {
			if issue.Position.Offset < 0 || issue.Position.Offset > len(source) {
				t.Fatal("diagnostic outside source", issue)
			}
		}
	})
}

func TestPartialGroupedImportsPreserveSymbolOffsets(t *testing.T) {
	source := "fn first() -> Int:\n    return 1\nimport {\nList,\nMap,\n} from \"@std/collections.ms\"\nfn broken(\nfn later() -> Int:\n    return 2\n"
	module, issues := ParsePartial("grouped.ms", source)
	if len(issues) == 0 || len(module.Imports) != 2 || len(module.Declarations) != 2 {
		t.Fatal(module, issues)
	}
	for _, imp := range module.Imports {
		if imp.NamePos.Offset != strings.Index(source, imp.Name+",") {
			t.Fatal(imp)
		}
	}
}

func TestPartialDefaultsPreserveExpressionPositions(t *testing.T) {
	source := "fn broken(\nfn later(first: Int = 3, second: Int = first + 1) -> Int:\n    return second\n"
	module, issues := ParsePartial("defaults.ms", source)
	if len(issues) == 0 || len(module.Declarations) != 1 {
		t.Fatal(module, issues)
	}
	value := module.Declarations[0].Params[1].Default
	if value.Left.Pos.Line != 2 || value.Left.Pos.Offset != strings.Index(source, "first +") || value.Right.Pos.Offset != strings.Index(source, "1)") {
		t.Fatal("default expression positions were not rebased", value)
	}
}
