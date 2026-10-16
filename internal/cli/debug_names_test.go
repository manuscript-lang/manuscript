package cli

import (
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestDebugNamesMapGeneratedLocalsFunctionsAndStatementLines(t *testing.T) {
	span := func(file string, start, line int) tooling.Span {
		return tooling.Span{File: file, Start: start, Line: line}
	}
	names := namesFromInspection("/work", tooling.Inspection{
		Sources:  []tooling.Source{{File: "src/main.ms"}},
		Entities: []tooling.Entity{{Kind: "type", Name: "Point", Span: span("src/main.ms", 0, 1)}, {Kind: "fn", Name: "main", Span: span("src/main.ms", 20, 4)}, {Kind: "fn", Name: "helper", Span: span("src/main.ms", 90, 12)}},
		// The first statement after main's header is on line 5; the one at line 9 is later.
		Statements: []tooling.Span{span("src/main.ms", 40, 5), span("src/main.ms", 70, 9), span("src/main.ms", 120, 13)},
	})
	if names.Root != "/work" || !names.Sources["src/main.ms"] {
		t.Fatalf("names: %+v", names)
	}
	byName := map[string]int{}
	for _, entity := range names.Entities {
		byName[entity.Name] = entity.Body
		if entity.Function != (entity.Name != "Point") {
			t.Fatalf("only functions are breakpoint targets: %+v", entity)
		}
	}
	if byName["main"] != 5 || byName["helper"] != 13 {
		t.Fatalf("function breakpoints should stop on the first body statement: %v", byName)
	}
	for _, line := range []int{4, 5, 9, 12, 13} {
		if !names.Lines["src/main.ms"][line] {
			t.Errorf("line %d should be a statement or declaration line", line)
		}
	}
	if names.Lines["src/main.ms"][6] {
		t.Error("a blank generated-glue line is not a statement line")
	}
}

func TestDebugNamesIncludeSourceAccessorBodies(t *testing.T) {
	const source = `interface Counter:
    get next -> Int
type State:
    count: Int
impl Counter for State:
    get next -> Int:
        self.count = self.count + 1
        return self.count
fn read(state: State) -> Int:
    return state.next
`
	result := compiler.CompileSource("accessors.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	names := debugNames(result)
	found := map[string]bool{}
	for _, entity := range names.Entities {
		switch entity.Name {
		case "Counter.next":
			if entity.Function {
				t.Fatalf("an interface accessor has no executable body: %+v", entity)
			}
			found[entity.Name] = true
		case "Counter for State.next":
			if !entity.Function || entity.Body != 7 {
				t.Fatalf("a source accessor breakpoint must stop before its body: %+v", entity)
			}
			found[entity.Name] = true
		}
	}
	if len(found) != 2 {
		t.Fatalf("missing accessor declarations: %+v", names.Entities)
	}
}
