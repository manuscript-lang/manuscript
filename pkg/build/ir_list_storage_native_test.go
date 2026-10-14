package build

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIRListLiteralUsesPrimitiveBacking(t *testing.T) {
	const source = `import List from "@std/collections.ms"
fn ints() -> List[Int]: return [-9223372036854775808, 1, 9223372036854775807]
fn floats() -> List[Float]: return [1.5, 2.5, 3.5]
fn bools() -> List[Bool]: return [true, false, true]
fn strings() -> List[String]: return ["é", "λ", "🙂"]
fn nested() -> List[List[Int]]:
    let shared = [1]
    return [shared, shared]
fn visit(values: List[Int], value: Int) -> Int:
    values.append(value)
    return value
fn effects(values: List[Int]) -> List[Int]:
    return [visit(values, 3), visit(values, 1), visit(values, 2)]
`
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileSourceForBuild("ir-lists.ms", source, compiler.Options{}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			if !strings.Contains(result.Source, "rt.NewList(") || strings.Contains(result.Source, "&rt.List{") {
				t.Fatal("exercised IR path bypasses primitive construction")
			}
			var replacements []string
			for _, name := range []string{"ints", "floats", "bools", "strings", "nested", "effects"} {
				replacements = append(replacements, "@@"+name+"@@", result.Program.Symbol("ir-lists.ms", name).ID)
			}
			harness := strings.NewReplacer(replacements...).Replace(`
func checkIRLists() {
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 for _,test:=range []struct{factory rt.Value; values []rt.Value}{
  {@@ints@@,[]rt.Value{int64(-9223372036854775808),int64(1),int64(9223372036854775807)}},
  {@@floats@@,[]rt.Value{float64(1.5),float64(2.5),float64(3.5)}},
  {@@bools@@,[]rt.Value{true,false,true}},
  {@@strings@@,[]rt.Value{"é","λ","🙂"}},
 } {
  first:=test.factory.(rt.Function).Body(ctx,nil).(*rt.List)
  second:=test.factory.(rt.Function).Body(ctx,nil).(*rt.List)
  if first==second || first.Items!=nil || second.Items!=nil || first.Len()!=len(test.values) {panic("IR primitive literal has boxed/shared backing")}
  for i,want:=range test.values {if first.Get(i)!=want || second.Get(i)!=want {panic("IR literal changed checked payload")}}
  first.Set(0,test.values[1]);if second.Get(0)!=test.values[0] {panic("IR literal evaluations share backing")}
 }
 nested:=@@nested@@.(rt.Function).Body(ctx,nil).(*rt.List)
 if nested.Items==nil || nested.Get(0)!=nested.Get(1) || nested.Get(0).(*rt.List).Items!=nil {panic("IR nested literal lost boxed fallback or shallow identity")}
 visits:=rt.NewIntList("@std/List[Int]",nil)
 effects:=@@effects@@.(rt.Function).Body(ctx,[]rt.Value{visits}).(*rt.List)
 if effects.Items!=nil || effects.Len()!=3 || visits.Len()!=3 {panic("IR effectful literal lost primitive backing")}
 for i,want:=range []int64{3,1,2} {if effects.Capture().Int(i)!=want || visits.Capture().Int(i)!=want {panic("IR operand evaluation order changed")}}
}
`)
			generated := strings.Replace(result.Source, "\tinitialize()\n", "\tinitialize()\n\tcheckIRLists()\n", 1) + harness
			binary := filepath.Join(t.TempDir(), "ir-lists")
			if err := Build(generated, binary); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("native IR backing: %v\n%s", err, out)
			}
		})
	}
}
