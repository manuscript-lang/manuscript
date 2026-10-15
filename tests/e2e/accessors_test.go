package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestAccessorReceiversComposeWithStandardContractOperations(t *testing.T) {
	result := compiler.CompileSource("accessor-contract-operations.ms", `import panic from "@std/faults.ms"
import {Clock, Instant, clock} from "@std/time.ms"

type ClockReader:
    operation: fn() -> Instant

impl Clock for ClockReader:
    fn now() -> Instant: self.operation()

interface Selection:
    get current -> Clock

type State:
    selected: Clock
    reads: Int

impl Selection for State:
    get current -> Clock:
        self.reads = self.reads + 1
        return self.selected

fn observe(value: Selection) -> Instant: value.current.now()

test "standard operations read accessor receivers once and retain current values":
    let native = clock()
    let first = Clock(ClockReader(fn() -> Instant: native.now())).now()
    let state = State(native, 0)
    let view = Selection(state)
    let second = observe(view)
    state.selected = Clock(ClockReader(fn() -> Instant: native.now()))
    let third = observe(view)
    state.selected = native
    let fourth = observe(view)
    if state.reads != 3 or second.difference(first).nanoseconds < 0 or third.difference(second).nanoseconds < 0 or fourth.difference(third).nanoseconds < 0:
        return panic("operation lowering repeated an accessor or cached its result")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("accessor standard-contract integration: %v\n%s", err, output)
	}
}

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

func TestAccessorsComposeWithDefaultConstructorsAndNativeCalls(t *testing.T) {
	result := compiler.CompileSource("accessor-main512.ms", `import panic from "@std/faults.ms"
interface Size:
    get length -> Int
    fn scaled(factor: Int) -> Int
type Counter:
    size: Int
    reads: Int
impl Size for Counter:
    get length -> Int:
        self.reads = self.reads + 1
        return self.size
    fn scaled(factor: Int) -> Int: self.size * factor
type Options:
    source: Counter
    observed: Int = source.length
    parts: List[String] = "a,b".split(",")
fn via_view(value: Size) -> Int: value.length + value.scaled(2)
test "accessors compose with merged optimizations":
    let counter = Counter(3, 0)
    let first = Options(counter)
    if first.observed != 3 or first.parts.length != 2 or counter.reads != 1:
        return panic("constructor default read changed")
    counter.size = 4
    if via_view(Size(counter)) != 12 or counter.reads != 2:
        return panic("interface method cache changed accessor reads")
    let second = Options(counter, 99, ["explicit"])
    if second.observed != 99 or counter.reads != 2:
        return panic("explicit constructor arguments executed defaults")
    if "a-b-c".replace("-", "+") != "a+b-c" or "abc".is_empty:
        return panic("native optional defaults or scalar reads changed")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "1 tests, 0 failed") {
		t.Fatalf("accessor main integration: %v\n%s", err, output)
	}
}
