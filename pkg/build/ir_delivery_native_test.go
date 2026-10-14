package build

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIRCancelledSourceReturnDelivery(t *testing.T) {
	source := `fn escaped(stop: fn() -> Unit) -> Int:
    let result: Int = match some(7):
        some(value):
            stop()
            return value
        none: 0
    return result
`
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileSourceForBuild("delivery.ms", source, compiler.Options{}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			id := result.Program.Symbol("delivery.ms", "escaped").ID
			harness := strings.NewReplacer("@@id@@", id, "@@native@@", id+"Native").Replace(`
func verifyDelivery(){
 for _,native:=range []bool{true,false} {
  ctx:=rt.RootExecution();var cancel context.CancelFunc;ctx.Context,cancel=context.WithCancel(ctx.Context)
  stop:=rt.Function{Result:"Unit",Body:func(*rt.Execution,[]rt.Value)rt.Value{cancel();return rt.Unit{}}}
  var value rt.Value;var failure any
  func(){defer func(){failure=recover()}();if native {value=@@native@@(ctx,stop)} else {value=@@id@@.(rt.Function).Body(ctx,[]rt.Value{stop})}}()
  if failure==nil || value!=nil {panic(fmt.Sprintf("cancelled sourceReturn delivered=%v failure=%T native=%v",value,failure,native))}
  rt.FinishExecution(ctx)
 }
}
`)
			generated := strings.Replace(result.Source, "package main\n", "package main\nimport (\"context\";\"fmt\")\n", 1)
			generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tverifyDelivery()\n", 1) + harness
			binary := filepath.Join(t.TempDir(), "delivery")
			if err := BuildWithType(generated, binary, kind); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("%v\n%s", err, out)
			}
		})
	}
}
