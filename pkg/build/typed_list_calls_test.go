package build

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestGeneratedTypedListCallsAndComparatorBoundaries(t *testing.T) {
	source := `import panic from "@std/faults.ms"
fn compare(left: Int, right: Int) -> Int: left - right
fn floating(left: Float, right: Float) -> Int:
    if left < right: return -1
    if left > right: return 1
    return 0
fn read(values: List[Int], index: Int) -> Int: values.at(index).unwrap()
fn captured() -> fn(left: Int, right: Int) -> Int:
    let bias = 1000
    return fn(left: Int, right: Int) -> Int: (left + bias) - (right + bias)
fn argument_fault() -> Int: compare(1, panic("argument failure"))
fn append_fault(values: List[Int]) -> Unit:
    values.append(panic("append failure"))
`
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileSourceForBuild("typed-list.ms", source, compiler.Options{}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			var replacements []string
			for _, name := range []string{"compare", "floating", "read", "captured", "argument_fault", "append_fault"} {
				replacements = append(replacements, "@@"+name+"@@", result.Program.Symbol("typed-list.ms", name).ID)
			}
			harness := strings.NewReplacer(replacements...).Replace(`
var typedResult rt.Value
func caught(body func())(failure any){defer func(){failure=recover()}();body();return}
type observedContext struct { context.Context; checks int }
func(c *observedContext)Err()error {c.checks++;return c.Context.Err()}
func verifyTypedCalls(){
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 observed:=&observedContext{Context:ctx.Context};ctx.Context=observed
 compare:=@@compare@@.(rt.Function)
 if compare.IntCompare==nil {panic("missing named typed comparator")}
 if compare.IntCompare(ctx,10000,20000)!=-10000 || observed.checks!=2 {panic(fmt.Sprintf("callback guard checks=%d",observed.checks))}
 observed.checks=0
 if compare.Body(ctx,[]rt.Value{int64(10000),int64(20000)}).(int64)!=-10000 || observed.checks!=2 {panic("boxed callback guard changed")}
 direct:=caught(func(){compare.IntCompare(ctx,math.MaxInt64,-1)})
 boxed:=caught(func(){compare.Body(ctx,[]rt.Value{int64(math.MaxInt64),int64(-1)})})
 if !reflect.DeepEqual(direct,boxed) {panic(fmt.Sprintf("comparator fault/frame parity: %#v != %#v",direct,boxed))}
 floating:=@@floating@@.(rt.Function)
 if floating.FloatCompare==nil || floating.FloatCompare(ctx,math.NaN(),1)!=0 || floating.FloatCompare(ctx,math.Copysign(0,-1),0)!=0 {panic("Float callback behavior")}
 captured:=@@captured@@.(rt.Function).Body(ctx,nil).(rt.Function)
 if captured.IntCompare==nil || captured.IntCompare(ctx,10000,20000)!=-10000 || captured.Body(ctx,[]rt.Value{int64(10000),int64(20000)}).(int64)!=-10000 {panic("captured callback parity")}
 values:=rt.NewIntList("@std/List[Int]",[]int64{10000,20000})
 args:=[]rt.Value{values,int64(-1)}
 if @@read@@.(rt.Function).Body(ctx,args)!=int64(20000) {panic("relative typed read")}
 if allocations:=testing.AllocsPerRun(100,func(){typedResult=@@read@@.(rt.Function).Body(ctx,args)});allocations>1 {panic(fmt.Sprintf("read allocations %g",allocations))}
 args[1]=int64(4)
 failure:=caught(func(){@@read@@.(rt.Function).Body(ctx,args)})
 if fault,ok:=failure.(rt.Fault);!ok || !strings.Contains(fault.Message,"Optional.unwrap() on none") || len(fault.Frames)==0 || !strings.Contains(fault.Frames[0],"in read") {panic(fmt.Sprintf("typed absent fault %#v",failure))}
 for _,f:=range []rt.Value{@@argument_fault@@,@@append_fault@@} {
  failure:=caught(func(){f.(rt.Function).Body(ctx,[]rt.Value{values})})
  if fault,ok:=failure.(rt.Fault);!ok || !strings.Contains(fault.Message,"failure") {panic(fmt.Sprintf("Never argument %#v",failure))}
 }
 cancelled:=rt.RootExecution();var cancel context.CancelFunc;cancelled.Context,cancel=context.WithCancel(cancelled.Context);cancel()
 if caught(func(){compare.IntCompare(cancelled,1,2)})==nil {panic("typed callback cancelled admission")}
 rt.FinishExecution(cancelled)
}
`)
			generated := strings.Replace(result.Source, "package main\n", "package main\nimport (\"context\";\"fmt\";\"math\";\"reflect\";\"strings\";\"testing\")\n", 1)
			generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tverifyTypedCalls()\n", 1) + harness
			binary := filepath.Join(t.TempDir(), "program")
			if err := BuildWithType(generated, binary, kind); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("native boundary: %v\n%s", err, out)
			}
		})
	}
}
