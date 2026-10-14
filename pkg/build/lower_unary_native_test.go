package build

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestUnaryLoweringNativeBoundaries(t *testing.T) {
	r := compiler.CompileSource("unary.ms", `fn negate(value: Int) -> Int: -value
fn negate_float(value: Float) -> Float: -value
fn operand_fault() -> Int: -(1 / 0)
fn composed(value: Int) -> Int: -value + +value
`, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	harness := strings.NewReplacer("@@negate@@", r.Program.Symbol("unary.ms", "negate").ID, "@@float@@", r.Program.Symbol("unary.ms", "negate_float").ID, "@@operand@@", r.Program.Symbol("unary.ms", "operand_fault").ID, "@@composed@@", r.Program.Symbol("unary.ms", "composed").ID).Replace(`
func unaryFailure(body func())(failure any){defer func(){failure=recover()}();body();return}
func checkUnary(){
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 for _,value:=range []int64{0,1,-1,math.MaxInt64,-math.MaxInt64} {
  if got:=@@negate@@.(rt.Function).Body(ctx,[]rt.Value{value});got!=-value {panic("integer negation changed")}
 }
 if @@composed@@.(rt.Function).Body(ctx,[]rt.Value{int64(1000)})!=int64(0){panic("composed unary changed")}
 for _,value:=range []float64{0,math.Copysign(0,-1),math.NaN(),math.Inf(1),math.Inf(-1)} {
  got:=rt.FloatValue(@@float@@.(rt.Function).Body(ctx,[]rt.Value{value}))
  if math.Float64bits(got)!=math.Float64bits(-value){panic("IEEE negation changed")}
 }
 for _,test:=range []struct{fn rt.Value;args []rt.Value;frame string;message string}{
  {@@negate@@,[]rt.Value{int64(math.MinInt64)},"unary.ms:1:31 in negate","Int overflow"},
  {@@operand@@,nil,"unary.ms:3:32 in operand_fault","division by zero"},
 } {
  failure:=unaryFailure(func(){test.fn.(rt.Function).Body(ctx,test.args)})
  fault,ok:=failure.(rt.Fault)
  if !ok || len(fault.Frames)!=1 || fault.Frames[0]!=test.frame || !strings.Contains(fault.Message,test.message){panic(fmt.Sprintf("unary fault: %#v want %s",failure,test.frame))}
 }
}
`)
	generated := strings.Replace(r.Source, "package main\n", "package main\nimport (\"math\";\"fmt\";\"strings\")\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckUnary()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "program")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("unary boundaries: %v\n%s", err, out)
	}
}
