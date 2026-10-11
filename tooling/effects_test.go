package tooling_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/compiler"
	"github.com/manuscript-lang/manuscript/tooling"
)

func TestEffectsIncludeTransitiveCallsAndImplicitCleanup(t *testing.T) {
	source := `import Closeable from "@std/cleanup.ms"
import State from "@std/state.ms"

type Resource:
    state: State[Bool]

impl Closeable for Resource:
    fn close() -> Unit:
        self.state.set(value: true)

fn pure() -> Int:
    return 1

fn direct(resource: Resource) -> Unit:
    with item = resource:
        assert true

fn transitive(resource: Resource) -> Unit:
    direct(resource: resource)

fn nested(resource: Resource) -> Unit:
    let callback = fn() -> Unit:
        with item = resource:
            assert true

fn indirect(callback: fn() -> Unit) -> Unit:
    callback()
`
	result := compiler.CompileSource("effects.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	inspection := tooling.Inspect(result.Program)
	found := map[string][]string{}
	for _, entity := range inspection.Entities {
		found[entity.Name] = entity.Effects
	}
	for _, name := range []string{"direct", "transitive", "nested", "Closeable for Resource.close"} {
		if !reflect.DeepEqual(found[name], []string{"write"}) {
			t.Errorf("%s effects: %v", name, found[name])
		}
	}
	if len(found["pure"]) != 0 || !reflect.DeepEqual(found["indirect"], []string{"unknown"}) {
		t.Fatal(found)
	}
	cleanupCalls := 0
	for _, site := range inspection.Calls {
		if site.Kind == "cleanup" {
			cleanupCalls++
			if !strings.Contains(site.Target, "#method#") {
				t.Fatal("unresolved concrete cleanup target", site)
			}
		}
	}
	if cleanupCalls != 2 {
		t.Fatal("missing implicit cleanup sites", cleanupCalls)
	}
}
