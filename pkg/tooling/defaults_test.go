package tooling_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
	"github.com/manuscript-lang/manuscript/pkg/tooling/format"
)

func TestDefaultExpressionsParticipateInTooling(t *testing.T) {
	source := `import Queue from "@std/queues.ms"
fn read(state: Queue[Int]) Int:
    return state.length()
fn named(state: Queue[Int], value: Int = read(state)) Int:
    return value
fn nested(state: Queue[Int]) Unit:
    let callback = fn(value: Int = read(state)) Int:
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
	formatted, err := format.Format("defaults.ms", source)
	if err != nil || !strings.Contains(formatted, "value: Int = read(state)") {
		t.Fatal(formatted, err)
	}
}
