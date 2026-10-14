package build

import (
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestPerformanceIssueNativeSemantics(t *testing.T) {
	var literals []string
	for i := 0; i < 1600; i++ {
		literals = append(literals, strconv.Itoa(i))
	}
	source := `fn large() -> List[Int]: [` + strings.Join(literals, ",") + `]
fn defaulted(first: Int, second: Int = first + 1) -> Int: first * 10 + second
fn defaults() -> Int: defaulted(first: 2)
fn ordered(a: Int, b: Int) -> Int: a * 10 + b
fn reordered() -> Int:
    var value = 1
    return ordered(b: value, a: match some(1):
        some(_):
            value = 7
            value
        none: 0
    )
fn literal_order() -> List[Int]:
    var value = 7
    return [value, match some(1):
        some(_):
            value = 9
            value
        none: 0
    ]
fn receiver_order() -> Int:
    var values = [7]
    return values.at(match some(1):
        some(_):
            values = [9]
            0
        none: 0
    ).unwrap()
fn iteration() -> Int:
    let values = [1, 2, 3]
    var total = 0
    for value in values:
        if value == 1:
            values.set(1, 4)
            values.append(5)
        total = total + value
    return total
`
	r := compiler.CompileSource("perf.ms", source, compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	var replacements []string
	for _, name := range []string{"large", "defaults", "reordered", "literal_order", "receiver_order", "iteration"} {
		replacements = append(replacements, "@@"+name+"@@", r.Program.Symbol("perf.ms", name).ID)
	}
	harness := strings.NewReplacer(replacements...).Replace(`
func checkPerformanceSemantics(){
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 first:=@@large@@.(rt.Function).Body(ctx,nil).(*rt.List)
 second:=@@large@@.(rt.Function).Body(ctx,nil).(*rt.List)
 if first.Len()!=1600 || first.Get(1599)!=int64(1599){panic("large literal data changed")}
 first.Set(0,int64(99));if second.Get(0)!=int64(0){panic("literal evaluations share backing")}
 clone:=rt.Clone(first).(*rt.List);clone.Set(1,int64(98));if first.Get(1)!=int64(1){panic("clone shares outer backing")}
 for _,test:=range []struct{fn rt.Value;want int64}{{@@defaults@@,23},{@@reordered@@,71},{@@receiver_order@@,7},{@@iteration@@,8}} {
  if got:=test.fn.(rt.Function).Body(ctx,nil);got!=test.want {panic(fmt.Sprintf("scalar semantics: %v != %d",got,test.want))}
 }
 values:=@@literal_order@@.(rt.Function).Body(ctx,nil).(*rt.List)
 if values.Get(0)!=int64(7)||values.Get(1)!=int64(9){panic("literal evaluation order changed")}
}
`)
	generated := strings.Replace(r.Source, "package main\n", "package main\nimport \"fmt\"\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckPerformanceSemantics()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "program")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("performance semantics: %v\n%s", err, out)
	}
}
