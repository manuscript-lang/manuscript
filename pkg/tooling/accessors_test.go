package tooling_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestFormatAccessorDeclarationsIsIdempotent(t *testing.T) {
	const source = `interface Sized:
    get length->Int
    fn get()->Int
type Buffer:
    count:Int
impl Sized for Buffer:
    get length->Int: return self.count
    fn get()->Int: return self.count
`
	formatted, err := tooling.Format("accessors.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"get length -> Int", "get length -> Int: return self.count", "fn get() -> Int"} {
		if !strings.Contains(formatted, want) {
			t.Fatalf("format lost %q: %s", want, formatted)
		}
	}
	twice, err := tooling.Format("accessors.ms", formatted)
	if err != nil || twice != formatted {
		t.Fatalf("not idempotent: %q, %v", twice, err)
	}
}

func TestInspectionIncludesAccessorExecutionButNotMethodReferences(t *testing.T) {
	const source = `interface Counter:
    get next -> Int
    fn read() -> Int
type State:
    count: Int
impl Counter for State:
    get next -> Int:
        self.count = self.count + 1
        return self.count
    fn read() -> Int:
        return self.count
fn use(state: State) -> Int:
    let callable = state.read
    return state.next
`
	result := compiler.CompileSource("accessors.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	if inspection.Format != 2 {
		t.Fatal("accessor inspection requires schema version 2", inspection.Format)
	}
	reads := 0
	for _, site := range inspection.Calls {
		if site.Kind == "accessor" {
			reads++
			if !strings.Contains(site.Target, "#accessor#") {
				t.Fatalf("accessor target lost checked identity: %+v", site)
			}
		} else if site.Kind == "operation" {
			t.Fatalf("a bound method reference executed: %+v", site)
		}
	}
	if reads != 1 || !strings.Contains(tooling.Diagram(inspection), "-->|accessor|") {
		t.Fatal("missing accessor execution", inspection.Calls)
	}
	for _, entity := range inspection.Entities {
		if entity.Name == "Counter for State.next" && (entity.Kind != "accessor" || entity.Type != "Int" || !slices.Contains(entity.Effects, "write")) {
			t.Fatalf("accessor entity lost its value type/effects: %+v", entity)
		}
		if entity.Name == "use" && !slices.Contains(entity.Effects, "write") {
			t.Fatalf("accessor read lost transitive effects: %+v", entity)
		}
	}
}

func TestInspectionKeepsInterfaceAccessorTargets(t *testing.T) {
	const source = `interface Sized:
    get length -> Int
fn size[T: Sized](value: T) -> Int:
    return value.length
fn viewed(value: Sized) -> Int:
    return value.length
`
	result := compiler.CompileSource("contracts.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	target := ""
	for _, entity := range inspection.Entities {
		if entity.Name == "Sized.length" {
			if entity.Kind != "accessor" || entity.Type != "Int" {
				t.Fatal("contract member lost accessor value metadata", entity)
			}
			target = entity.ID
		}
	}
	if target == "" || len(inspection.Calls) != 2 {
		t.Fatal("contract reads missing", inspection)
	}
	for _, site := range inspection.Calls {
		if site.Kind != "accessor" || site.Target != target {
			t.Fatal("generic/view read lost its checked contract target", site)
		}
	}
}

func TestStandardInspectionDistinguishesAccessorsAndErrorMethods(t *testing.T) {
	inspection := tooling.StandardDeclarations()
	if inspection.Format != 2 {
		t.Fatal("standard inspection schema is not versioned with accessor metadata")
	}
	found := map[string]bool{}
	for _, entity := range inspection.Entities {
		switch entity.Name {
		case "List.length", "Bytes.length", "SynchronizedGuard.value":
			if entity.Kind != "accessor" || entity.Type == "" || strings.HasPrefix(entity.Type, "fn(") {
				t.Fatal("native accessor exported its implementation callable instead of a value", entity)
			}
			found[entity.Name] = true
		case "Error.message", "JsonError.message":
			if entity.Kind != "operation" {
				t.Fatal("Error.message implementation changed into an accessor", entity)
			}
			found[entity.Name] = true
		}
	}
	if len(found) != 5 {
		t.Fatal("standard inspection omitted required member metadata", found)
	}
}
