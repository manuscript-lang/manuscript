package e2e_test

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestBuilderAndRangeQueryStates(t *testing.T) {
	var source, builders, ranges strings.Builder
	source.WriteString(`import StringBuilder from "@std/string.ms"
import Closeable from "@std/cleanup.ms"
type Resource:
    visits: List[Int]
impl Closeable for Resource:
    fn close() Unit:
        self.visits.append(1)
`)
	probes := map[string]string{}
	index := 0
	for _, fragment := range []string{"", "x", "é日\n", strings.Repeat("x", 128)} {
		for _, n := range []int{256, 257, 319, 320, 321} {
			if len(fragment) == 128 && n != 321 {
				continue
			}
			name := fmt.Sprintf("builder%d", index)
			index++
			update := "b.append(" + strconv.Quote(fragment) + ")\n                i += 1"
			fmt.Fprintf(&source, "fn %s(visits: List[Int], scoped: Bool) String:\n    let b = StringBuilder()\n    var i = 0\n    if scoped:\n        with resource = Resource(visits):\n            while i < %d:\n                %s\n    else:\n        while i < %d:\n            b.append(%s)\n            i += 1\n    return b.freeze()\n", name, n, update, n, strconv.Quote(fragment))
			fmt.Fprintf(&builders, "{%s,%d,%s},\n", name, n, strconv.Quote(fragment))
			probes[name] = "observeBuilder(ctx,i,b)"
		}
	}
	for _, n := range []int{0, 1, 63, 64, 65, 256, 257, 319, 320, 321} {
		for _, sign := range []int{1, -1} {
			name := fmt.Sprintf("range%d", index)
			index++
			var values strings.Builder
			for i := 0; i < n; i++ {
				if i > 0 {
					values.WriteString(",")
				}
				fmt.Fprint(&values, i%7-3)
			}
			op := "+="
			if sign < 0 {
				op = "-="
			}
			fmt.Fprintf(&source, "fn %s(visits: List[Int], scoped: Bool) Int:\n    let values: List[Int] = [%s]\n    var sum = 0\n    if scoped:\n        with resource = Resource(visits):\n            for x in values:\n                sum %s x\n    else:\n        for x in values:\n            sum %s x\n    return sum\n", name, values.String(), op, op)
			fmt.Fprintf(&ranges, "{%s,%d,%d},\n", name, n, sign)
			probes[name] = "observeRange(ctx,x,sum)"
		}
	}
	r := compiler.CompileSource("group-states.ms", source.String(), compiler.Options{})
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if got := strings.Count(r.Source, " >= 3"); got != 20 {
		t.Fatalf("selected%d unrolled loops, want20", got)
	}
	if got := strings.Count(r.Source, " - i"); got != 32 {
		t.Fatalf("selected%d builder loops, want32", got)
	}
	generated := strings.Replace(r.Source, "package main", "package main\nimport (\"context\";\"reflect\";\"strings\";\"fmt\")", 1)
	generated = strings.Replace(generated, "func main()", "func unusedMain()", 1)
	for name, observer := range probes {
		start := strings.Index(generated, "func "+name+"(")
		if start < 0 {
			t.Fatal(name)
		}
		end := strings.Index(generated[start+1:], "\nfunc ")
		if end < 0 {
			t.Fatal("no next declaration")
		}
		end += start + 1
		part := generated[start:end]
		if strings.HasPrefix(name, "range") {
			original := part
			offset := 0
			for {
				q := strings.Index(original[offset:], "rt.CheckCancelled(ctx)")
				if q < 0 {
					break
				}
				q += offset
				names := regexp.MustCompile(`\b(x\w*)\s*:=`).FindAllStringSubmatch(original[:q], -1)
				if len(names) == 0 {
					t.Fatal("missing current element")
				}
				observer = "observeRange(ctx," + names[len(names)-1][1] + ",sum)"
				original = original[:q] + observer + original[q+len("rt.CheckCancelled(ctx)"):]
				offset = q + len(observer)
			}
			part = original
		} else {
			part = strings.ReplaceAll(part, "rt.CheckCancelled(ctx)", observer)
		}

		generated = generated[:start] + part + generated[end:]
	}
	generated += `
 var builderStates []struct{i int;text string}
 var rangeStates [][2]int
 var cancelAt int
 var cancelNow context.CancelFunc
 func observeBuilder(ctx *rt.Execution,i int,b *rt.StringBuilder) rt.Unit {
  text:=string(reflect.ValueOf(b).Elem().FieldByName("text").Bytes())
  builderStates=append(builderStates,struct{i int;text string}{i,text})
  if len(builderStates)==cancelAt {cancelNow()}
  return rt.CheckCancelled(ctx)
 }
 func observeRange(ctx *rt.Execution,x,sum int) rt.Unit {
  rangeStates=append(rangeStates,[2]int{x,sum})
  if len(rangeStates)==cancelAt {cancelNow()}
  return rt.CheckCancelled(ctx)
 }
 func runProbe(n int, mode string,stop int,probe func(*rt.Execution,*rt.List[int],bool)) {
  ctx:=rt.RootExecution();ctx.Context,cancelNow=context.WithCancel(context.Background())
  defer cancelNow()
  if mode=="nil" {ctx=nil};if mode=="shield" {ctx=rt.Shield(ctx)}
  if mode=="background" {ctx.Context=context.Background()}
  visits:=rt.NewList[int]();cancelAt=stop;completed:=false
  shouldCancel:=mode=="cancel"&&stop>0
  func(){defer func(){if r:=recover();r!=nil {if !shouldCancel||!strings.HasSuffix(fmt.Sprintf("%T",r),".cancelled") {panic(r)}}}();probe(ctx,visits,ctx!=nil);completed=true}()
  if completed==shouldCancel {panic("wrong completion")}
  if ctx!=nil {if len(visits.Items)!=1 {panic("wrong cleanup")}} else if len(visits.Items)!=0 {panic("unexpected cleanup")}
 }
 func main(){
  builders:=[]struct{probe func(*rt.Execution,*rt.List[int],bool)string;n int;fragment string}{
 ` + builders.String() + `}
  for _,tc:=range builders {for _,mode:=range []string{"cancel","nil","background","shield"} {for _,stop:=range []int{0,1,tc.n/64} {
   builderStates=nil
   runProbe(tc.n,mode,stop,func(ctx *rt.Execution,v *rt.List[int],scoped bool){if got:=tc.probe(ctx,v,scoped);got!=strings.Repeat(tc.fragment,tc.n) {panic("wrong builder result")}})
   count:=tc.n/64;if mode=="cancel"&&stop>0 {count=stop}
   if len(builderStates)!=count {panic("wrong builder query count")}
   for q,state:=range builderStates {offset:=64*(q+1)-1;if state.i!=offset||state.text!=strings.Repeat(tc.fragment,offset) {panic("wrong builder query state")}}
  }}}
  ranges:=[]struct{probe func(*rt.Execution,*rt.List[int],bool)int;n,sign int}{
 ` + ranges.String() + `}
  for _,tc:=range ranges {for _,mode:=range []string{"cancel","nil","background","shield"} {for _,stop:=range []int{0,1,tc.n/64} {
   if stop>tc.n/64 {continue}
   rangeStates=nil
   want:=0;for i:=0;i<tc.n;i++ {want+=tc.sign*(i%7-3)}
   runProbe(tc.n,mode,stop,func(ctx *rt.Execution,v *rt.List[int],scoped bool){if got:=tc.probe(ctx,v,scoped);got!=want {panic("wrong range result")}})
   count:=tc.n/64;if mode=="cancel"&&stop>0 {count=stop}
   if len(rangeStates)!=count {panic("wrong range query count")}
   for q,state:=range rangeStates {offset:=64*(q+1)-1;sum:=0;for i:=0;i<offset;i++ {sum+=tc.sign*(i%7-3)};if state!=[2]int{offset%7-3,sum} {panic("wrong range query state")}}
  }}}
 }
 `
	for _, standalone := range []bool{false, true} {
		native := generated
		if standalone {
			var err error
			native, err = build.Standalone(native)
			if err != nil {
				t.Fatal(err)
			}
		}
		binary := filepath.Join(t.TempDir(), "group-states")
		if err := build.Build(native, binary); err != nil {
			t.Fatal(err)
		}
		if output, err := commandOutput(t, binary); err != nil {
			t.Fatalf("standalone=%v: %v\n%s", standalone, err, output)
		}
	}
}

func TestBuilderAndRangeFaultFrames(t *testing.T) {
	for _, tc := range []struct {
		name, source, frame string
		appendFault         bool
	}{
		{"builder query", "import StringBuilder from \"@std/string.ms\"\nfn probe() String:\n    let b = StringBuilder()\n    var i = 0\n    while i < 321:\n        b.append(\"x\")\n        i += 1\n    return b.freeze()\n", "group-fault.ms:5 in probe", false},
		{"builder append", "import StringBuilder from \"@std/string.ms\"\nfn probe() String:\n    let b = StringBuilder()\n    var i = 0\n    while i < 321:\n        b.append(\"x\")\n        i += 1\n    return b.freeze()\n", "group-fault.ms:6 in probe", true},
		{"range query", "fn probe() Int:\n    let values = [" + strings.TrimSuffix(strings.Repeat("1,", 256), ",") + "]\n    var sum = 0\n    for x in values:\n        sum += x\n    return sum\n", "group-fault.ms:4 in probe", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := compiler.CompileSource("group-fault.ms", tc.source, compiler.Options{})
			if !r.Success() {
				t.Fatal(r.Diagnostics)
			}
			if !strings.Contains(r.Source, " := 321 - i") && !strings.Contains(r.Source, " >= 3") {
				t.Fatal("grouping not selected")
			}
			generated := strings.Replace(r.Source, "package main", "package main\nimport (\"context\";\"fmt\";\"strings\")", 1)
			generated = strings.Replace(generated, "func main()", "func unusedMain()", 1)
			setup, message := "ctx.Context=queryFaultContext{context.Background()}", "query fault"
			if tc.appendFault {
				generated = strings.ReplaceAll(generated, "rt.StringBuilder_Append(ctx, b,", "faultAppend(ctx, b,")
				setup, message = "", "builder is sealed"
			}
			generated += `
   type queryFaultContext struct {context.Context}
   func (queryFaultContext) Err() error {rt.Raise("query fault");return nil}
   func faultAppend(ctx *rt.Execution,b *rt.StringBuilder,value string) rt.Unit {rt.StringBuilder_Freeze(ctx,b);return rt.StringBuilder_Append(ctx,b,value)}
   func main(){
    defer func(){value:=recover();fault,ok:=value.(rt.Fault);if !ok||fault.Message!=` + strconv.Quote(message) + `||strings.Join(fault.Frames,"\n")!=` + strconv.Quote(tc.frame) + ` {panic(fmt.Sprintf("unexpected fault: %#v",value))}}()
    ctx:=rt.RootExecution()
   ` + setup + `
    probe(ctx)
    panic("did not fault")
   }
  `
			for _, standalone := range []bool{false, true} {
				native := generated
				if standalone {
					var err error
					native, err = build.Standalone(native)
					if err != nil {
						t.Fatal(err)
					}
				}
				binary := filepath.Join(t.TempDir(), "group-fault")
				if err := build.Build(native, binary); err != nil {
					t.Fatal(err)
				}
				if output, err := commandOutput(t, binary); err != nil {
					t.Fatalf("standalone=%v: %v\n%s", standalone, err, output)
				}
			}
		})
	}
}
