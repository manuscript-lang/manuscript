package compiler

import (
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/checker"
)

func TestGeneratedMethodAdmissionBoundary(t *testing.T) {
	source := `interface Probe:
    fn probe(amount: Int) -> Int
type Counter:
    entered: Int
impl Probe for Counter:
    fn probe(amount: Int) -> Int:
        self.entered = self.entered + 1
        return amount + 1
fn call(counter: Counter, amount: Int) -> Int: counter.probe(amount)
fn call_cold(counter: Counter, amount: Int) -> Int: counter.probe(amount)
`
	r := CompileSource("method-admission.ms", source, Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if !strings.Contains(r.Source, "rt.CallMethod(") {
		t.Fatal("fixture did not emit the direct method router")
	}
	harness := strings.NewReplacer(
		"@@call@@", r.Program.Symbols["method-admission.ms"]["call"].ID,
		"@@call_cold@@", r.Program.Symbols["method-admission.ms"]["call_cold"].ID,
		"@@Counter@@", strconv.Quote(checker.TypeKey(r.Program.Symbols["method-admission.ms"]["Counter"].Type)),
	).Replace(`
type admissionContext struct { context.Context; count, cancelAt int }
func (c *admissionContext) Err() error { c.count++; if c.cancelAt>0 && c.count>=c.cancelAt {return context.Canceled};return c.Context.Err() }
func admissionFailure(body func()) (failure any) { defer func(){ failure=recover() }();body();return }
func checkMethodAdmission() {
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 observed:=&admissionContext{Context:ctx.Context};ctx.Context=observed
 receiver:=rt.ConstructWithContext(nil,@@Counter@@,[]rt.Argument{{Name:"entered",Value:int64(0)}})
 fn:=@@call@@.(rt.Function);args:=[]rt.Value{receiver,int64(6)}
 for _,cached:=range []bool{false,true} {
  observed.count=0
  if got:=fn.Body(ctx,args);got!=int64(7) || observed.count!=4 {panic(fmt.Sprintf("cached=%v got=%v cancellation observations=%d, want4 (caller+method)",cached,got,observed.count))}
 }
 if rt.IntValue(rt.Field(receiver,"entered"))!=2 {panic("method did not execute exactly once per invocation")}
 // Caller admission succeeds; cancellation reaches the method's own guard.
 for _,methodCaller:=range []rt.Function{@@call_cold@@.(rt.Function),fn} {
  observed.count=0;observed.cancelAt=2
  if admissionFailure(func(){methodCaller.Body(ctx,args)})==nil || rt.IntValue(rt.Field(receiver,"entered"))!=2 {panic("cancelled method entered after caller admission")}
 }
 observed.cancelAt=0
 var cancel context.CancelFunc;observed.Context,cancel=context.WithCancel(observed.Context);cancel()
 if admissionFailure(func(){fn.Body(ctx,args)})==nil || rt.IntValue(rt.Field(receiver,"entered"))!=2 {panic("cancelled method entered")}
}
`)
	generated := strings.Replace(r.Source, "package main\n", "package main\nimport(\"context\";\"fmt\")\n", 1)
	profiles := t.TempDir()
	checks := "\tinitialize()\n\tcheckMethodAdmission()\n\tif rt.Profile(" + strconv.Quote(filepath.Join(profiles, "cpu.pprof")) + ", \"\", " + strconv.Quote(filepath.Join(profiles, "trace.out")) + ", func() int { checkMethodAdmission();return 0 }) != 0 { panic(\"profile failed\") }\n"
	generated = strings.Replace(generated, "\tinitialize()\n", checks, 1) + harness
	binary := filepath.Join(t.TempDir(), "program")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("emitted method admission: %v\n%s", err, out)
	}
}
