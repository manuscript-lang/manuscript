package tooling_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestDefaultExpressionsParticipateInTooling(t *testing.T) {
	source := `import SynchronizedGuard from "@std/sync.ms"
fn read(state: SynchronizedGuard[Int]) -> Int:
    return state.get()
fn named(state: SynchronizedGuard[Int], value: Int = read(state)) -> Int:
    return value
fn nested(state: SynchronizedGuard[Int]) -> Unit:
    let callback = fn(value: Int = read(state)) -> Int:
        return value
`
	result := compiler.CompileSource("defaults.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	for _, entity := range inspection.Entities {
		if !reflect.DeepEqual(entity.Effects, []string{"read"}) {
			t.Errorf("%s: defaults omitted from effects: %v", entity.Name, entity.Effects)
		}
	}
	defaults := 0
	for _, call := range inspection.Calls {
		if call.Target == "defaults.ms#fn#read" {
			defaults++
		}
	}
	if defaults != 2 {
		t.Fatal("default calls missing from inspection", inspection.Calls)
	}
	nav, ok := tooling.NavigationAt(result.Program, "defaults.ms", strings.Index(source, "read(state))"))
	if !ok || nav.Definition.Start != strings.Index(source, "fn read") {
		t.Fatal("default call navigation", nav, ok)
	}
	formatted, err := tooling.Format("defaults.ms", source)
	if err != nil || !strings.Contains(formatted, "value: Int = read(state)") {
		t.Fatal(formatted, err)
	}
}
