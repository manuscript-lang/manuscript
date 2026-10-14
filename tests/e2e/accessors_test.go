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
