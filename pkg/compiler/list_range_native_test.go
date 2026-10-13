package compiler

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestListRangeNativeFaultAndCancellation(t *testing.T) {
	const source = `import List from "@std/collections.ms"
import panic from "@std/faults.ms"
fn callback_fault(values: List[Int]) -> Unit:
    values.for_each(fn(value):
        values.without(0)
        panic("range failure")
    )
fn callback_cancel(values: List[Int], stop: fn() -> Unit) -> Unit:
    values.for_each(fn(value):
        values.with_values(start: 0, delete_count: values.length(), replacement: [])
        stop()
    )
`
	result := CompileSource("native-range.ms", source, Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	harness := strings.NewReplacer(
		"@@fault@@", result.Program.Symbols["native-range.ms"]["callback_fault"].ID,
		"@@cancel@@", result.Program.Symbols["native-range.ms"]["callback_cancel"].ID,
	).Replace(`
func rangeFailure(body func()) (failure any) {defer func(){failure=recover()}();body();return}
func checkRangeExits() {
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 values:=&rt.List{Type:"@std/List[Int]",Items:[]rt.Value{int64(1),int64(2),int64(3)}}
 alias:=values
 failure:=rangeFailure(func(){@@fault@@.(rt.Function).Body(ctx,[]rt.Value{values})})
 fault,ok:=failure.(rt.Fault)
 if !ok || fault.Message!="range failure" || len(fault.Frames)!=2 || !strings.HasPrefix(fault.Frames[0],"native-range.ms:6:") || !strings.HasPrefix(fault.Frames[1],"native-range.ms:4:") {panic(fmt.Sprintf("fault/source changed: %#v",failure))}
 if !reflect.DeepEqual(alias.Items,[]rt.Value{int64(2),int64(3)}) {panic("fault lost source mutation")}
 cancelled:=rt.RootExecution();defer rt.FinishExecution(cancelled)
 var cancel context.CancelFunc
 cancelled.Context,cancel=context.WithCancel(cancelled.Context);defer cancel()
 count:=0
 stop:=rt.NewFunction(nil,"Unit",func(*rt.Execution,[]rt.Value)rt.Value{count++;cancel();return rt.Unit{}})
 values=&rt.List{Type:"@std/List[Int]",Items:[]rt.Value{int64(1),int64(2),int64(3)}}
 failure=rangeFailure(func(){@@cancel@@.(rt.Function).Body(cancelled,[]rt.Value{values,stop})})
 expected:=rangeFailure(func(){rt.CheckCancelled(cancelled)})
 if failure==nil || !reflect.DeepEqual(failure,expected) || count!=1 || len(values.Items)!=0 || !reflect.DeepEqual(values.Items[:3],[]rt.Value{int64(1),int64(2),int64(3)}) {panic(fmt.Sprintf("cancel/source changed: %#v",failure))}
}
`)
	generated := strings.Replace(result.Source, "package main\n", "package main\nimport (\"context\";\"reflect\";\"strings\";\"fmt\")\n", 1)
	generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tcheckRangeExits()\n", 1) + harness
	binary := filepath.Join(t.TempDir(), "range")
	if err := Build(generated, binary); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(binary).CombinedOutput(); err != nil {
		t.Fatalf("native range exits: %v\n%s", err, output)
	}
}
