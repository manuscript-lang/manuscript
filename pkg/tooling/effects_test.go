package tooling_test

import (
	"reflect"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

func TestEffectsIncludeTransitiveCallsAndImplicitCleanup(t *testing.T) {
	source := `import Closeable from "@std/cleanup.ms"
import Synchronized from "@std/sync.ms"

type Resource:
    state: Synchronized[Bool]

impl Closeable for Resource:
    fn close() -> Unit:
        with locked = self.state.lock():
            locked.set(value: true)

fn pure() -> Int:
    return 1

fn direct(resource: Resource) -> Unit:
    with item = resource:
        return

fn transitive(resource: Resource) -> Unit:
    direct(resource: resource)

fn nested(resource: Resource) -> Unit:
    let callback = fn() -> Unit:
        with item = resource:
            return

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
		if !reflect.DeepEqual(found[name], []string{"read", "write"}) {
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
			if !strings.Contains(site.Target, "#method#") && !strings.Contains(site.Target, "SynchronizedGuard") {
				t.Fatal("unresolved concrete cleanup target", site)
			}
		}
	}
	if cleanupCalls != 3 {
		t.Fatal("missing implicit cleanup sites", cleanupCalls)
	}
}

func TestEffectsIncludeRecordDefaults(t *testing.T) {
	source := `type State:
    count: Int
fn increment(state: State) -> Int:
    state.count = state.count + 1
    return state.count
type Options:
    state: State
    count: Int = increment(state)
fn construct(state: State) -> Options:
    return Options(state: state)
`
	result := compiler.CompileSource("field-effects.ms", source, compiler.Options{AnalyzeOnly: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	found := map[string][]string{}
	for _, entity := range tooling.Inspect(result.Program).Entities {
		found[entity.Name] = entity.Effects
	}
	for _, name := range []string{"Options", "construct"} {
		if !reflect.DeepEqual(found[name], []string{"read", "write"}) {
			t.Fatalf("%s lost constructor-default effects: %v", name, found[name])
		}
	}
}
