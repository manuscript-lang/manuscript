package build

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func repeatedLiteral(item string, count int) string {
	return "[" + strings.TrimSuffix(strings.Repeat(item+", ", count), ", ") + "]"
}

func TestLargeLiteralNativeSemantics(t *testing.T) {
	const count = 1100
	source := `import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"
type Counter:
    value: Int
    closed: Int

type Resource:
    counter: Counter
impl Closeable for Resource:
    fn close() -> Unit: self.counter.closed = self.counter.closed + 1

fn values() -> List[Int]: return @@ints@@
fn defaults(values: List[Int] = @@defaults@@) -> List[Int]: values
fn generic[T](value: T) -> List[T]: return @@generic@@
fn nested() -> List[List[Int]]: return @@nested@@
fn floats() -> List[Float]: return @@floats@@
fn bools() -> List[Bool]: return @@bools@@
fn texts() -> List[String]: return @@texts@@
fn tick(counter: Counter) -> Int:
    let value = counter.value
    counter.value = value + 1
    return value
fn effects(counter: Counter) -> List[Int]: return @@effects@@
fn ordered() -> List[Int]:
    var value = 7
    return @@ordered@@
fn early(value: Optional[Int]) -> Int:
    let discarded = @@early@@
    return discarded.length() - 1100
fn failing() -> Result[Int, String]: error("expected")
fn propagated() -> Result[List[Int], String]: return ok(@@try@@)
fn loop_exits(counter: Counter) -> Int:
    var iteration = 0
    while iteration < 3:
        iteration = iteration + 1
        with resource = Resource(counter):
            let discarded = @@loop@@
    return iteration

test "large literal fresh data defaults and aliases":
    let first = values()
    let second = values()
    let clone = first.clone()
    let sliced = first.slice(0, 2).unwrap()
    let alias = first
    let append = alias.append
    first.set(0, 123)
    if alias.at(0).unwrap() != 123 or second.at(0).unwrap() != 0 or clone.at(0).unwrap() != 0 or sliced.at(0).unwrap() != 0:
        return panic("fresh literal backing and shallow copies")
    append(9999)
    if first.length() != 1101 or alias.at(-1).unwrap() != 9999 or second.length() != 1100:
        return panic("saved append alias across growth")
    let default_first = defaults()
    default_first.set(0, 88)
    if defaults().at(0).unwrap() != 7: return panic("fresh default")
    let numbers = generic(9)
    numbers.set(0, 77)
    if generic(9).at(0).unwrap() != 9: return panic("fresh generic backing")
    let record = Counter(3, 0)
    let records = generic(record)
    let other_records = generic(record)
    records.at(0).unwrap().value = 11
    if other_records.at(-1).unwrap().value != 11: return panic("generic payload alias")

test "nested literals remain fresh and clones shallow":
    let first = nested()
    let other = nested()
    let clone = first.clone()
    first.at(0).unwrap().set(0, 9)
    if first.at(1).unwrap().at(0).unwrap() != 7 or other.at(0).unwrap().at(0).unwrap() != 7 or clone.at(0).unwrap().at(0).unwrap() != 9:
        return panic("nested freshness and shallow aliasing")

test "large checked primitive data preserves values":
    let floating = floats()
    if floating.length() != 1100 or floating.at(0).unwrap() != 0.0 or floating.at(1).unwrap() != 0.0 or floating.at(2).unwrap() != -1.25:
        return panic("binary64 constant values")
    if 1.0 / floating.at(0).unwrap() > 0.0 or 1.0 / floating.at(1).unwrap() > 0.0:
        return panic("negative zero and rounded underflow")
    if not bools().at(-1).unwrap() or texts().at(-1).unwrap() != "λ\n\"": return panic("Bool and String data")

test "large literal effect and plain local order":
    let counter = Counter(0, 0)
    let result = effects(counter)
    if counter.value != 1100: return panic("each effect once")
    for index in [0, 63, 64, 65, 1099]:
        if result.at(index).unwrap() != index: return panic("written effect order across helpers")
    let plain = ordered()
    if plain.at(0).unwrap() != 7 or plain.at(64).unwrap() != 9 or plain.at(65).unwrap() != 9:
        return panic("plain reads precede later mutation")

test "large literal exits retain cleanup and propagation":
    if early(some(29)) != 29 or early(none) != 0: return panic("enclosing return")
    let cause = match propagated():
        error(cause): cause
        ok(value): return panic("lost propagation")
    if cause != "expected": return panic("original error payload")
    let counter = Counter(0, 0)
    if loop_exits(counter) != 2 or counter.closed != 2: return panic("break continue and cleanup")
`
	numbers := make([]string, count)
	for at := range numbers {
		numbers[at] = fmt.Sprint(at)
	}
	ordered := "[value, " + strings.Repeat("0, ", 63) + `match some(1):
        some(payload):
            value = 9
            value
        none: 0
    , value, ` + strings.TrimSuffix(strings.Repeat("0, ", count-66), ", ") + "]"
	early := "[" + strings.Repeat("0, ", 64) + `match value:
        some(number): return number
        none: 0
    , ` + strings.TrimSuffix(strings.Repeat("0, ", count-65), ", ") + "]"
	loop := "[" + strings.Repeat("0, ", 64) + `match some(iteration):
                some(value):
                    if value == 1: continue
                    if value == 2: break
                    value
                none: 0
            , ` + strings.TrimSuffix(strings.Repeat("0, ", count-65), ", ") + "]"
	source = strings.NewReplacer(
		"@@ints@@", "["+strings.Join(numbers, ", ")+"]",
		"@@defaults@@", repeatedLiteral("7", count),
		"@@generic@@", repeatedLiteral("value", count),
		"@@nested@@", repeatedLiteral("[7]", count),
		"@@floats@@", "[-0.0, -1e-400, -1.25, "+strings.TrimSuffix(strings.Repeat("+1.25, ", count-3), ", ")+"]",
		"@@bools@@", repeatedLiteral("true", count),
		"@@texts@@", repeatedLiteral(`"λ\n\""`, count),
		"@@effects@@", repeatedLiteral("tick(counter)", count),
		"@@ordered@@", ordered,
		"@@early@@", early,
		"@@try@@", "["+strings.Repeat("0, ", 64)+"try failing(), "+strings.TrimSuffix(strings.Repeat("0, ", count-65), ", ")+"]",
		"@@loop@@", loop,
	).Replace(source)
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.RelWithDebInfo} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileSourceForBuild("large-literals.ms", source, compiler.Options{Tests: true}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(t.TempDir(), "large-literals")
			if _, err := BuildCheckedWithType(result, binary, "", kind); err != nil {
				t.Fatal(err)
			}
			data, err := exec.Command(binary).CombinedOutput()
			if err != nil || !strings.Contains(string(data), "5 tests, 0 failed") {
				t.Fatalf("native semantics: %v\n%s", err, data)
			}
		})
	}
}

func TestLargeLiteralFrozenBaselineParity(t *testing.T) {
	source, err := os.ReadFile("testdata/literal-data/program.ms")
	if err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile("testdata/literal-data/before.go.txt")
	if err != nil {
		t.Fatal(err)
	}
	result := compiler.CompileSource("literal.ms", string(source), compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, "rt.NewIntList(") {
		t.Fatal("optimized constructor not selected")
	}
	for _, source := range []string{string(before), result.Source} {
		binary := filepath.Join(t.TempDir(), "oracle")
		if err := Build(source, binary); err != nil {
			t.Fatal(err)
		}
		if data, err := exec.Command(binary).CombinedOutput(); err != nil {
			t.Fatalf("oracle execution: %v\n%s", err, data)
		}
	}
}

func TestLargeLiteralCancellationDuringInitialization(t *testing.T) {
	source := `type Counter:
    value: Int
fn tick(counter: Counter) -> Int:
    counter.value = counter.value + 1
    return counter.value
fn values(counter: Counter, operation: fn(counter: Counter) -> Int) -> List[Int]: return ` + repeatedLiteral("operation(counter)", 1100) + "\n"
	result := compiler.CompileSource("large-cancel.ms", source, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	tick := result.Program.Symbol("large-cancel.ms", "tick").ID
	values := result.Program.Symbol("large-cancel.ms", "values").ID
	counter := result.Program.Symbol("large-cancel.ms", "Counter").Type
	result.Source = strings.Replace(result.Source, "\"os\"", "\"os\"\n\"context\"\n\"reflect\"", 1)
	result.Source += fmt.Sprintf(`
func init() {
 initialize()
 root:=rt.RootExecution()
 defer rt.FinishExecution(root)
 cancelled:=*root
 var cancel context.CancelFunc
 cancelled.Context,cancel=context.WithCancel(root.Context)
 cancel()
 failure:=func(body func())(got any){defer func(){got=recover()}();body();return}
 expected:=failure(func(){rt.CheckCancelled(&cancelled)})
 c:=rt.NewRecord(%q,[]rt.Argument{{Name:"value",Value:int64(0)}})
 args:=[]rt.Value{c,%s.(rt.Function)}
 got:=failure(func(){%s.(rt.Function).Body(&cancelled,args)})
 if !reflect.DeepEqual(got,expected) || rt.IntValue(rt.Field(c,"value"))!=0 {os.Exit(81)}
 running:=*root
 running.Context,cancel=context.WithCancel(root.Context)
 defer cancel()
 original:=%s.(rt.Function)
 calls:=0
 replacement:=original
 replacement.Body=func(ctx *rt.Execution,args []rt.Value)rt.Value{
  calls++
  value:=original.Body(ctx,args)
  if calls==65 {cancel()}
  return value
 }
 args[1]=replacement
 got=failure(func(){%s.(rt.Function).Body(&running,args)})
 if !reflect.DeepEqual(got,expected) || calls!=66 || rt.IntValue(rt.Field(c,"value"))!=65 {os.Exit(82)}
}
`, checker.TypeKey(counter), tick, values, tick, values)
	binary := filepath.Join(t.TempDir(), "cancel")
	if _, err := BuildCheckedWithType(result, binary, "", compiler.Release); err != nil {
		t.Fatal(err)
	}
	if data, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("large initialization cancellation: %v\n%s", err, data)
	}
}

func TestLargeLiteralFaultKeepsSourceFrames(t *testing.T) {
	source := `fn fail(value: Int) -> Int:
    return 1 / value
fn values() -> List[Int]:
    return [` + strings.Repeat("7, ", 1099) + `fail(0)]
export fn main() -> Int:
    return values().length()
`
	result := compiler.CompileSource("large-fault.ms", source, compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	binary := filepath.Join(t.TempDir(), "fault")
	if _, err := BuildCheckedWithType(result, binary, "", compiler.Release); err != nil {
		t.Fatal(err)
	}
	data, err := exec.Command(binary).CombinedOutput()
	exit, ok := err.(*exec.ExitError)
	if !ok || exit.ExitCode() != 70 {
		t.Fatalf("expected source fault: %v\n%s", err, data)
	}
	output := string(data)
	for _, frame := range []string{"large-fault.ms:2:14 in fail", fmt.Sprintf("large-fault.ms:4:%d in values", strings.Index(strings.Split(source, "\n")[3], "fail(0)")+1), "large-fault.ms:6:12 in main"} {
		if !strings.Contains(output, frame) {
			t.Fatalf("missing %q in source frames:\n%s", frame, output)
		}
	}
	if strings.Count(output, "  at ") != 3 || strings.Contains(output, "temporary") || strings.Contains(output, "manuscript.generated.go") {
		t.Fatalf("initializer helper leaked into source frames:\n%s", output)
	}
}
