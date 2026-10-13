// bench-release-literals emits an unchanged checked Release baseline and
// benchmark-only root-free array-return factories. It changes no lowering.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func main() {
	output := flag.String("output", ".artifacts/release-literals", "retained artifacts")
	sizes := flag.String("sizes", "16000,100000", "source literal sizes")
	chunks := flag.String("chunks", "64,256,1024", "measured factory sizes")
	reuse := flag.Bool("reuse", false, "reuse one stack temporary for all returned arrays")
	typed := flag.Bool("typed-controls", false, "emit synthetic typed owner controls, not a runtime ABI")
	flag.Parse()
	for _, size := range strings.Split(*sizes, ",") {
		n, err := strconv.Atoi(size)
		if err != nil || n <= 0 {
			panic("invalid size")
		}
		values := make([]string, n)
		for i := range values {
			values[i] = strconv.Itoa(i)
		}
		source := "import List from \"@std/collections.ms\"\nfn values() -> List[Int]:\n    return [" + strings.Join(values, ", ") + "]\nexport fn main() -> Int:\n    return values().length() - " + size + "\n"
		r := compiler.CompileSource("flat.ms", source, compiler.Options{Entry: true})
		if !r.Success() {
			panic(r.Diagnostics)
		}
		start := strings.Index(r.Source, "Items: []rt.Value{")
		if start < 0 {
			panic("missing baseline constructor")
		}
		start += len("Items: ")
		end := strings.Index(r.Source[start:], "}") + start + 1
		elements := strings.Split(strings.TrimSuffix(strings.TrimPrefix(r.Source[start:end], "[]rt.Value{"), "}"), ", ")
		if len(elements) != n {
			panic("constructor parse mismatch")
		}
		variants := map[string]string{"baseline": r.Source}
		if *typed {
			original := `&rt.List{Type: "@std/List[Int]", Items: ` + r.Source[start:end] + `}`
			if !strings.Contains(r.Source, original) {
				panic("missing full baseline list")
			}
			for _, width := range []string{"32", "64"} {
				control := fmt.Sprintf(`
// Benchmark-only owner; it is not compatible with production List dispatch.
type literalAccess interface {length() int}
type literalHandle struct {Type string; storage literalAccess}
type literalOwner struct {literalHandle; items []int%s}
func (o *literalOwner) length() int {return len(o.items)}
func (o *literalOwner) append(v int%s) {o.items=append(o.items,v)}
func typedLiteral() *literalHandle {
 owner:= &literalOwner{items:append([]int%s(nil), literalData[:]...)}
 owner.literalHandle=literalHandle{Type:"@std/List[Int]",storage:owner}
 return &owner.literalHandle
}
var literalData = [%d]int%s{%s}
`, width, width, width, n, width, strings.Join(values, ", "))
				variants["typed"+width] = strings.Replace(r.Source, original, "typedLiteral()", 1) + control
			}
		}
		for _, chunk := range strings.Split(*chunks, ",") {
			k, err := strconv.Atoi(chunk)
			if err != nil || k <= 0 {
				panic("invalid chunk size")
			}
			var body, factories strings.Builder
			fmt.Fprintf(&body, "\nfunc freshLiteral() []rt.Value {\nvar items [%d]rt.Value\n", n)
			if *reuse {
				fmt.Fprintf(&body, "var part [%d]rt.Value\n", k)
			}
			for lo, part := 0, 0; lo < n; lo, part = lo+k, part+1 {
				hi := min(lo+k, n)
				if *reuse {
					fmt.Fprintf(&body, "part = literalPart%d()\ncopy(items[%d:%d], part[:%d])\n", part, lo, hi, hi-lo)
					fmt.Fprintf(&factories, "\nfunc literalPart%d() [%d]rt.Value {return [%d]rt.Value{%s}}\n", part, k, k, strings.Join(elements[lo:hi], ", "))
				} else {
					fmt.Fprintf(&body, "part%d := literalPart%d()\ncopy(items[%d:%d], part%d[:])\n", part, part, lo, hi, part)
					fmt.Fprintf(&factories, "\nfunc literalPart%d() [%d]rt.Value {return [%d]rt.Value{%s}}\n", part, hi-lo, hi-lo, strings.Join(elements[lo:hi], ", "))
				}
			}
			body.WriteString("return items[:]\n}\n")
			variants["factory"+chunk] = r.Source[:start] + "freshLiteral()" + r.Source[end:] + body.String() + factories.String()
		}
		symbol := r.Program.Symbols["flat.ms"]["values"].ID
		harness := fmt.Sprintf(`package main
import("testing"; rt "github.com/manuscript-lang/manuscript/pkg/runtime")
var sink rt.Value
func TestResult(t *testing.T) {
 initialize();ctx:=rt.RootExecution()
 first:=rt.Invoke(ctx,%s,nil).(*rt.List);second:=rt.Invoke(ctx,%s,nil).(*rt.List)
 if len(first.Items)!=%d || len(second.Items)!=%d {t.Fatal("length")}
 for i,v:=range first.Items {if rt.IntValue(v)!=int64(i) {t.Fatal("element",i,v)}}
 first.Items[0]=first.Items[%d-1];if rt.IntValue(second.Items[0])!=0 {t.Fatal("shared storage")}
}
func BenchmarkLiteral(b *testing.B) {initialize();ctx:=rt.RootExecution();b.ReportAllocs();b.ResetTimer();for i:=0;i<b.N;i++ {sink=rt.Invoke(ctx,%s,nil)}}
`, symbol, symbol, n, n, n, symbol)
		for name, goSource := range variants {
			variantHarness := harness
			if strings.HasPrefix(name, "typed") {
				variantHarness = fmt.Sprintf(`package main
import("testing"; rt "github.com/manuscript-lang/manuscript/pkg/runtime")
var sink rt.Value
func TestResult(t *testing.T) {
 initialize();ctx:=rt.RootExecution()
 first:=rt.Invoke(ctx,%s,nil).(*literalHandle);second:=rt.Invoke(ctx,%s,nil).(*literalHandle)
 owner:=first.storage.(*literalOwner);again:=second.storage.(*literalOwner)
 if first.storage.length()!=%d || second.storage.length()!=%d {t.Fatal("length")}
 for i,v:=range owner.items {if int64(v)!=int64(i) {t.Fatal("element",i,v)}}
 owner.items[0]=owner.items[%d-1];if again.items[0]!=0 {t.Fatal("shared storage")}
 // Boxed aliases and a saved typed projection must retain one owner across growth.
 var alias rt.Value=first
 projection:=owner; saved:=owner.append
 for i:=0;i<%d+1;i++ {saved(7)}
 if alias.(*literalHandle).storage!=projection || projection.length()!=2*%d+1 {t.Fatal("growth stranded an alias")}
}
func BenchmarkLiteral(b *testing.B) {initialize();ctx:=rt.RootExecution();b.ReportAllocs();b.ResetTimer();for i:=0;i<b.N;i++ {sink=rt.Invoke(ctx,%s,nil)}}
`, symbol, symbol, n, n, n, n, n, symbol)
			}
			dir := filepath.Join(*output, size, name)
			if err := os.MkdirAll(dir, 0755); err != nil {
				panic(err)
			}
			for filename, data := range map[string]string{"source.ms": source, "program.go": goSource, "program_test.go": variantHarness} {
				if err := os.WriteFile(filepath.Join(dir, filename), []byte(data), 0644); err != nil {
					panic(err)
				}
			}
		}
	}
}
