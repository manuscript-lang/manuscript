package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestAccessorLocalImplementationEvidence(t *testing.T) {
	result := compiler.CompileFile("testdata/projects/accessors/main.ms", compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("accessor evidence: %v\n%s", err, output)
	}
}

func TestAccessorReadRunsBeforeFailingTry(t *testing.T) {
	result := compiler.CompileSource("accessor-order.ms", `import panic from "@std/faults.ms"
type State:
    reads: Int
interface Read:
    get value -> Int
impl Read for State:
    get value -> Int:
        self.reads = self.reads + 1
        return self.reads
fn fail() -> Result[Int, String]: error("expected")
fn consume(first: Int, second: Int) -> Int: first + second
fn ordered(state: State) -> Result[Int, String]:
    return ok(consume(state.value, try fail()))
test "accessor read is an execution barrier before try":
    let state = State(0)
    let outcome = ordered(state)
    let expected: Result[Int, String] = error("expected")
    if outcome != expected or state.reads != 1:
        return panic("try skipped or repeated accessor execution")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("accessor try order: %v\n%s", err, output)
	}
}

func TestAccessorsWithDirectDefaultsAndLocalClosures(t *testing.T) {
	result := compiler.CompileSource("accessor-integration.ms", `import panic from "@std/faults.ms"
type State:
    items: List[Int]
    reads: Int
interface Read:
    get value -> Int
impl Read for State:
    get value -> Int:
        self.reads = self.reads + 1
        return self.items.length
fn supplied(state: State) -> Int:
    state.reads = state.reads + 10
    return 7
fn defaults(state: State, first: Int, next: Int = state.value + first) -> Int: next
fn closure_reads(state: State) -> Bool:
    let head = fn() -> Optional[Int]: state.items.first
    let status = fn() -> Result[Int, String]: ok(state.value)
    let absent = head()
    state.items.append(42)
    let present = head()
    let outcome = status()
    return absent.is_none and present.is_some and outcome.is_ok
test "accessors retain semantics in direct defaults and local closures":
    let state = State([], 0)
    if not closure_reads(state) or state.reads != 1:
        return panic("closure reads lost live values or typed flags")
    if defaults(state, supplied(state)) != 8 or state.reads != 12:
        return panic("default accessor did not run once after supplied argument")
    if defaults(state, 1, 99) != 99 or state.reads != 12:
        return panic("explicit argument executed omitted default")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("accessor direct-call integration: %v\n%s", err, output)
	}
}
