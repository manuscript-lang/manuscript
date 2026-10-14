package build

import (
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Instant has no source constructor. Inject only its opaque tick in a native
// harness, then exercise ordinary source methods/operators and source frames.
func TestTimeFaultNativeSourceFrames(t *testing.T) {
	source := `import {Instant, Duration} from "@std/time.ms"
fn shift(value: Instant, offset: Duration) -> Instant:
    return value.shift(offset)
fn difference(left: Instant, right: Instant) -> Duration:
    return left.difference(right)
fn plus(value: Instant, offset: Duration) -> Instant:
    return value + offset
fn minus(value: Instant, offset: Duration) -> Instant:
    return value - offset
fn elapsed(left: Instant, right: Instant) -> Duration:
    return left - right
`
	r := compiler.CompileSource("time-fault.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var replacements []string
	for _, name := range []string{"shift", "difference", "plus", "minus", "elapsed"} {
		replacements = append(replacements, "@@"+name+"@@", r.Program.Symbol("time-fault.ms", name).ID)
	}
	harness := strings.NewReplacer(replacements...).Replace(`
func timeFailure(body func()) (failure any) {defer func(){failure=recover()}();body();return}
func checkTimeFrames() {
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 for _,tc:=range []struct{fn rt.Value;args []rt.Value;message,frame string}{
  {@@shift@@,[]rt.Value{rt.Instant{Tick:9223372036854775807},rt.Duration(1)},"Instant.shift: overflow; found value (nanoseconds) 9223372036854775807 and duration (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807","time-fault.ms:3:18 in shift"},
  {@@difference@@,[]rt.Value{rt.Instant{Tick:9223372036854775807},rt.Instant{Tick:-1}},"Instant.difference: overflow; found value (nanoseconds) 9223372036854775807 and other (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807","time-fault.ms:5:17 in difference"},
  {@@plus@@,[]rt.Value{rt.Instant{Tick:9223372036854775807},rt.Duration(1)},"Instant.+: overflow; found value (nanoseconds) 9223372036854775807 and duration (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807","time-fault.ms:7:18 in plus"},
  {@@minus@@,[]rt.Value{rt.Instant{Tick:-9223372036854775808},rt.Duration(1)},"Instant.-: overflow; found value (nanoseconds) -9223372036854775808 and duration (nanoseconds) 1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807","time-fault.ms:9:18 in minus"},
  {@@elapsed@@,[]rt.Value{rt.Instant{Tick:9223372036854775807},rt.Instant{Tick:-1}},"Instant.-: overflow; found left (nanoseconds) 9223372036854775807 and right (nanoseconds) -1; result nanoseconds must be between -9223372036854775808 and 9223372036854775807","time-fault.ms:11:17 in elapsed"},
 } {
  failure:=timeFailure(func(){tc.fn.(rt.Function).Body(ctx,tc.args)})
  fault,ok:=failure.(rt.Fault)
  if !ok||fault.Message!=tc.message||len(fault.Frames)!=1||fault.Frames[0]!=tc.frame {panic(fmt.Sprintf("fault = %#v, expected %s at %s",failure,tc.message,tc.frame))}
 }
}
`)
	generated := strings.Replace(r.Source, "package main\n", "package main\nimport \"fmt\"\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckTimeFrames()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "program")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("native time faults: %v\n%s", err, output)
	}
}
