package compiler

import (
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

const nativeCallSource = `import Closeable from "@std/cleanup.ms"
fn add(left: Int, right: Int) -> Int: left + right
fn identity(value: Int) -> Int: value
fn forward(value: Int) -> Int: identity(value)
fn defaulted(value: Int = 1) -> Int: value + 1
fn generic[T](value: T) -> T: value
fn payload(value: Int) -> Optional[Int]: some(value)
fn ordered() -> Int:
    var number = 1
    return add(number, match some(1):
        some(value):
            number = number + 1
            value
        none: 0
    )
fn nested_return(value: Int) -> Int:
    return add(1, match some(value):
        some(found): return found + 1
        none: 0
    )
fn shorted() -> Bool: false and (1 / 0 == 0)
fn reordered() -> Int: add(right: 2, left: 1)
fn float_op(left: Float, right: Float) -> Float: left * right + 1.0
fn recurse(depth: Int) -> Int:
    if depth == 0: return 1
    return recurse(depth - 1)
type Counter:
    value: Int
type Resource:
    counter: Counter
impl Closeable for Resource:
    fn close() -> Unit: self.counter.value = self.counter.value + 1
fn cleanup(value: Int) -> Int:
    let counter = Counter(0)
    with active = Resource(counter):
        let copy = value
    return counter.value + value
fn overflow(value: Int) -> Int: value + 1
fn divide(value: Int) -> Int: value / 0
fn outer(value: Int) -> Int: divide(value)
`

func TestNativeCallPilotEligibility(t *testing.T) {
	r := CompileSource("native-calls.ms", nativeCallSource, Options{ExperimentalNativeCalls: true})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	for _, name := range []string{"add", "ordered", "nested_return", "shorted", "float_op", "recurse", "cleanup", "overflow", "divide", "outer"} {
		id := r.Program.Symbols["native-calls.ms"][name].ID
		if !strings.Contains(r.Source, "func "+id+"Native(") {
			t.Errorf("%s has no native entry", name)
		}
	}
	for _, name := range []string{"identity", "forward", "defaulted", "generic", "payload"} {
		id := r.Program.Symbols["native-calls.ms"][name].ID
		if strings.Contains(r.Source, "func "+id+"Native(") {
			t.Errorf("%s crossed the boxed eligibility boundary", name)
		}
	}
	for i := 0; i < 3; i++ {
		repeated := CompileSource("native-calls.ms", nativeCallSource, Options{ExperimentalNativeCalls: true})
		if !repeated.Success() || repeated.Source != r.Source {
			t.Fatal("nondeterministic native call output", repeated.Diagnostics)
		}
	}
}

func TestNativeCallPilotExecution(t *testing.T) {
	for _, kind := range []BuildType{Release, Debug} {
		var baseline string
		for _, enabled := range []bool{false, true} {
			r := CompileSourceForBuild("native-calls.ms", nativeCallSource, Options{ExperimentalNativeCalls: enabled}, kind)
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			var replacements []string
			for name, s := range r.Program.Symbols["native-calls.ms"] {
				replacements = append(replacements, "@@"+name+"@@", s.ID)
			}
			harness := strings.NewReplacer(replacements...).Replace(`
func callFailure(body func()) (failure any) { defer func(){failure=recover()}();body();return }
func checkNativeCalls() {
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 for _,c:=range []struct{fn rt.Function; args []rt.Value; want rt.Value}{
  {@@ordered@@.(rt.Function),nil,int64(2)},
  {@@nested_return@@.(rt.Function),[]rt.Value{int64(7)},int64(8)},
  {@@shorted@@.(rt.Function),nil,false},
  {@@reordered@@.(rt.Function),nil,int64(3)},
  {@@cleanup@@.(rt.Function),[]rt.Value{int64(7)},int64(8)},
  {@@recurse@@.(rt.Function),[]rt.Value{int64(1024)},int64(1)},
 } { if got:=c.fn.Body(ctx,c.args);got!=c.want {panic(fmt.Sprintf("got %#v want %#v",got,c.want))} }
 // Pair native and boxed faults by printing their complete source Fault values.
 for _, c:=range []struct{fn rt.Function;arg int64}{
  {@@overflow@@.(rt.Function),math.MaxInt64},
  {@@divide@@.(rt.Function),1},
  {@@outer@@.(rt.Function),1},
 } {
  failure:=callFailure(func(){c.fn.Body(ctx,[]rt.Value{c.arg})})
  if _,ok:=failure.(rt.Fault);!ok {panic(fmt.Sprintf("lost source fault: %#v",failure))}
  fmt.Printf("%#v\n",failure)
 }
 for _, pair:=range [][2]float64{{math.NaN(),1},{math.Inf(1),0},{math.Copysign(0,-1),1},{1.0000000074505806,0.9999999925494194}} {
  got:=@@float_op@@.(rt.Function).Body(ctx,[]rt.Value{pair[0],pair[1]}).(float64)
  want:=float64(pair[0]*pair[1])+1
  if math.Float64bits(got)!=math.Float64bits(want) && !(math.IsNaN(got)&&math.IsNaN(want)) {panic("per-operation rounding changed")}
 }
}
`)
			generated := strings.Replace(r.Source, "package main\n", "package main\nimport(\"fmt\";\"math\")\n", 1)
			profiles := t.TempDir()
			checks := "\tinitialize()\n\tcheckNativeCalls()\n\tif rt.Profile(" + strconv.Quote(filepath.Join(profiles, "cpu.pprof")) + ", \"\", " + strconv.Quote(filepath.Join(profiles, "trace.out")) + ", func() int { checkNativeCalls(); return 0 }) != 0 { panic(\"profile failed\") }\n"
			generated = strings.Replace(generated, "\tinitialize()\n", checks, 1) + harness
			binary := filepath.Join(t.TempDir(), "program")
			if err := BuildWithType(generated, binary, kind); err != nil {
				t.Fatal(err)
			}
			out, err := exec.Command(binary).CombinedOutput()
			if err != nil {
				t.Fatalf("kind=%v enabled=%v: %v\n%s", kind, enabled, err, out)
			}
			if enabled {
				if string(out) != baseline {
					t.Fatalf("kind=%v: native faults differ from boxed:\n%s\n%s", kind, out, baseline)
				}
			} else {
				baseline = string(out)
			}
		}
	}
}
