package build

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestScalarLoweringNativeBoundaries(t *testing.T) {
	source := `import Closeable from "@std/cleanup.ms"
fn floats(left: Float, right: Float) -> Bool: left == right
fn strings(left: String, right: String) -> Bool: left == right
fn unequal(left: Float, right: Float) -> Bool: left != right
fn fault_left() -> Bool:
    return (1 / 0) == 1
fn fault_right() -> Bool:
    return 1 == (1 / 0)
fn fault_caller() -> Bool: fault_right()
fn empty() -> Unit: return
type Counter:
    value: Int
type Resource:
    counter: Counter
impl Closeable for Resource:
    fn close() -> Unit:
        self.counter.value = self.counter.value + 1
fn cancelled_with(resource: Resource, stop: fn() -> Unit) -> Unit:
    with active = resource: stop()
fn cancelled_empty(stop: fn() -> Unit) -> Unit: stop()
import panic from "@std/faults.ms"
type Broken:
    counter: Counter
impl Closeable for Broken:
    fn close() -> Unit:
        self.counter.value = self.counter.value + 1
        panic("secondary")
fn fault_with(resource: Resource, broken: Broken) -> Unit:
    with active = resource:
        with failing = broken: panic("primary")
`
	r := compiler.CompileSource("native.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var replacements []string
	for _, name := range []string{"floats", "strings", "unequal", "fault_left", "fault_right", "fault_caller", "empty", "cancelled_with", "cancelled_empty", "fault_with"} {
		replacements = append(replacements, "@@"+name+"@@", r.Program.Symbols["native.ms"][name].ID)
	}
	for _, name := range []string{"Counter", "Resource", "Broken"} {
		replacements = append(replacements, "@@"+name+"@@", strconv.Quote(checker.TypeKey(r.Program.Symbols["native.ms"][name].Type)))
	}
	// The native harness exercises IEEE values not expressible as source literals,
	// and cancellation after admission with and without a registered cleanup.
	harness := strings.NewReplacer(replacements...).Replace(`
func loweringFailure(body func()) (failure any) { defer func(){failure=recover()}(); body(); return }
func checkLowering() {
 ctx:=rt.RootExecution(); defer rt.FinishExecution(ctx)
 for _, pair:=range [][2]float64{{math.NaN(),math.NaN()},{math.Inf(1),math.Inf(1)},{math.Inf(1),math.Inf(-1)},{0,math.Copysign(0,-1)}} {
  args:=[]rt.Value{pair[0],pair[1]}
  if @@floats@@.(rt.Function).Body(ctx,args).(bool)!=(pair[0]==pair[1]) {panic("IEEE equality changed")}
  if @@unequal@@.(rt.Function).Body(ctx,args).(bool)!=(pair[0]!=pair[1]) {panic("IEEE inequality changed")}
 }
 for _, pair:=range [][2]string{{"é","e\u0301"},{"λ🙂","λ🙂"},{"",""},{"\x00","\x00"}} {
  if @@strings@@.(rt.Function).Body(ctx,[]rt.Value{pair[0],pair[1]}).(bool)!=(pair[0]==pair[1]) {panic("string equality changed")}
 }
 for _, test:=range []struct{fn rt.Value; frames []string}{
  {@@fault_left@@,[]string{"native.ms:6:15 in fault_left"}},
  {@@fault_right@@,[]string{"native.ms:8:20 in fault_right"}},
  {@@fault_caller@@,[]string{"native.ms:8:20 in fault_right","native.ms:9:28 in fault_caller"}},
 } {
  failure:=loweringFailure(func(){test.fn.(rt.Function).Body(ctx,nil)})
  fault,ok:=failure.(rt.Fault)
  if !ok || !reflect.DeepEqual(fault.Frames,test.frames) {panic(fmt.Sprintf("fault frames: %#v, want %v",failure,test.frames))}
 }
 for _, withCleanup:=range []bool{false,true} {
  execution:=rt.RootExecution()
  var cancel context.CancelFunc
  execution.Context,cancel=context.WithCancel(execution.Context)
  counter:=rt.ConstructWithContext(execution,@@Counter@@,[]rt.Argument{{Name:"value",Value:int64(0)}})
  resource:=rt.ConstructWithContext(execution,@@Resource@@,[]rt.Argument{{Name:"counter",Value:counter}})
  stop:=rt.NewFunction(nil,"Unit",func(*rt.Execution,[]rt.Value)rt.Value{cancel();return rt.Unit{}})
  failure:=loweringFailure(func(){
   if withCleanup {@@cancelled_with@@.(rt.Function).Body(execution,[]rt.Value{resource,stop})} else {@@cancelled_empty@@.(rt.Function).Body(execution,[]rt.Value{stop})}
  })
  expected:=loweringFailure(func(){rt.CheckCancelled(execution)})
  if failure==nil || !reflect.DeepEqual(failure,expected) {panic(fmt.Sprintf("cancellation changed: %#v != %#v",failure,expected))}
  want:=int64(0);if withCleanup {want=1}
  if rt.IntValue(rt.Field(counter,"value"))!=want {panic("cancelled cleanup changed")}
  rt.FinishExecution(execution)
 }
 counter:=rt.ConstructWithContext(ctx,@@Counter@@,[]rt.Argument{{Name:"value",Value:int64(0)}})
 resource:=rt.ConstructWithContext(ctx,@@Resource@@,[]rt.Argument{{Name:"counter",Value:counter}})
 broken:=rt.ConstructWithContext(ctx,@@Broken@@,[]rt.Argument{{Name:"counter",Value:counter}})
 failure:=loweringFailure(func(){@@fault_with@@.(rt.Function).Body(ctx,[]rt.Value{resource,broken})})
 fault,ok:=failure.(rt.Fault)
 if !ok || fault.Message!="primary" || len(fault.Secondary)!=1 || !strings.Contains(fault.Secondary[0],"secondary") || rt.IntValue(rt.Field(counter,"value"))!=2 {panic(fmt.Sprintf("cleanup primary/secondary changed: %#v",failure))}
 cancelled:=rt.RootExecution();defer rt.FinishExecution(cancelled)
 var cancel context.CancelFunc
 cancelled.Context,cancel=context.WithCancel(cancelled.Context);cancel()
 if loweringFailure(func(){@@empty@@.(rt.Function).Body(cancelled,nil)})==nil {panic("entry cancellation lost")}
}
`)
	generated := strings.Replace(r.Source, "package main\n", "package main\nimport (\"context\"; \"math\"; \"reflect\"; \"fmt\"; \"strings\")\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckLowering()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "program")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("native boundaries: %v\n%s", err, out)
	}
}
