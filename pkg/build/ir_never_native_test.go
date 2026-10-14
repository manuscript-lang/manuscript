package build

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestIRNeverExpectedNativeBoundaries(t *testing.T) {
	var source strings.Builder
	source.WriteString("import panic from \"@std/faults.ms\"\n")
	for _, scalar := range []string{"Int", "Float", "Bool", "String"} {
		fmt.Fprintf(&source, "fn index_%[1]s(values: List[%[1]s]) -> %[1]s: values.at(panic(\"index failure\")).unwrap()\n", scalar)
		fmt.Fprintf(&source, "fn match_%[1]s(values: List[%[1]s]) -> %[1]s:\n    return match values.at(100):\n        some(value): value\n        none: panic(\"match failure\")\n", scalar)
	}
	source.WriteString(`fn condition() -> Int:
    if panic("condition failure"): return 1
    return 0
fn looping() -> Int:
    while panic("while failure"): return 1
    return 0
fn and_left() -> Bool: panic("and lhs failure") and true
fn and_right() -> Bool: true and panic("and rhs failure")
fn or_left() -> Bool: panic("or lhs failure") or false
fn or_right() -> Bool: false or panic("or rhs failure")
fn negation() -> Bool: not panic("not failure")
fn skipped_and() -> Bool: false and panic("skipped")
fn skipped_or() -> Bool: true or panic("skipped")
fn defaulted(value: Int = panic("default failure")) -> Int: value + 1
fn omission() -> Int: defaulted()
`)
	for _, kind := range []compiler.BuildType{compiler.Release, compiler.Debug} {
		t.Run(string(kind), func(t *testing.T) {
			result := compiler.CompileSourceForBuild("never.ms", source.String(), compiler.Options{}, kind)
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			var harness strings.Builder
			harness.WriteString(`
func verifyNever(){
 ctx:=rt.RootExecution();defer rt.FinishExecution(ctx)
 check:=func(name string,body func()) {failure:=caughtNever(body);fault,ok:=failure.(rt.Fault);if !ok || !strings.Contains(fault.Message,"failure") || len(fault.Frames)==0 || !strings.Contains(fault.Frames[0],"in "+name) {panic(fmt.Sprintf("%s: %#v",name,failure))}}
`)
			for _, scalar := range []string{"Int", "Float", "Bool", "String"} {
				fmt.Fprintf(&harness, "values%s:=rt.NewList(\"@std/List[%s]\",nil)\n", scalar, scalar)
				for _, prefix := range []string{"index_", "match_"} {
					name := prefix + scalar
					id := result.Program.Symbol("never.ms", name).ID
					fmt.Fprintf(&harness, "check(%q,func(){_=%sNative(ctx,values%s)})\n", name, id, scalar)
					fmt.Fprintf(&harness, "check(%q,func(){_=%s.(rt.Function).Body(ctx,[]rt.Value{values%s})})\n", name, id, scalar)
				}
			}
			for _, name := range []string{"condition", "looping", "and_left", "and_right", "or_left", "or_right", "negation", "omission"} {
				id := result.Program.Symbol("never.ms", name).ID
				expected := name
				if name == "omission" {
					expected = "defaulted"
				}
				fmt.Fprintf(&harness, "check(%q,func(){_=%sNative(ctx)})\n", expected, id)
				fmt.Fprintf(&harness, "check(%q,func(){_=%s.(rt.Function).Body(ctx,nil)})\n", expected, id)
			}
			fmt.Fprintf(&harness, "if %sNative(ctx) || !%sNative(ctx){panic(\"short circuit\")}\n", result.Program.Symbol("never.ms", "skipped_and").ID, result.Program.Symbol("never.ms", "skipped_or").ID)
			harness.WriteString("}\nfunc caughtNever(body func())(failure any){defer func(){failure=recover()}();body();return}\n")
			generated := strings.Replace(result.Source, "package main\n", "package main\nimport (\"fmt\";\"strings\")\n", 1)
			generated = strings.Replace(generated, "\tinitialize()\n", "\tinitialize()\n\tverifyNever()\n", 1) + harness.String()
			binary := filepath.Join(t.TempDir(), "never")
			if err := BuildWithType(generated, binary, kind); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("%v\n%s", err, out)
			}
		})
	}
}
