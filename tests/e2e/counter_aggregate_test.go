package e2e_test

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"math"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestCounterAggregateQueryStates(t *testing.T) {
	var source, cases strings.Builder
	source.WriteString(`import Closeable from "@std/cleanup.ms"
type AggregateResource:
    visits: List[Int]
impl Closeable for AggregateResource:
    fn close() Unit:
        self.visits.append(1)
interface AggregateCounter:
    fn bump(by: Int) Int
    fn lower(by: Int) Int
type AggregateCell:
    total: Int
impl AggregateCounter for AggregateCell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
    fn lower(by: Int) Int:
        self.total -= by
        return self.total
fn identity[T](value: T) T: return value
`)
	states := map[string]string{}
	index := 0
	for _, kind := range []string{"affine-add", "affine-subtract", "negative-constant", "cell-add", "cell-subtract"} {
		affine := strings.HasPrefix(kind, "affine")
		record := strings.HasPrefix(kind, "cell")
		sign := 1
		if kind == "negative-constant" || strings.HasSuffix(kind, "subtract") {
			sign = -1
		}
		for _, n := range []int{256, 257, 319, 320, 321} {
			starts := []int64{0, -1000}
			if !affine {
				starts = append(starts, math.MinInt64, math.MaxInt64-int64(n))
			}
			for _, start := range starts {
				name := fmt.Sprintf("probe%d", index)
				setup, update, returned, state := "var sum = 0", "sum += identity[Int](i)", "sum", "sum"
				if kind == "affine-subtract" {
					update = "sum -= identity[Int](i)"
				}
				if kind == "negative-constant" {
					update = "sum += -3"
				}
				if record {
					setup, update, returned, state = "let cell = AggregateCell(0)", "cell.bump(3)", "cell.total", "cell.Total"
				}
				if kind == "cell-subtract" {
					update = "cell.lower(3)"
				}
				fmt.Fprintf(&source, "fn %s(visits: List[Int], scoped: Bool) Int:\n    %s\n    var i = %d\n    if scoped:\n        with resource = AggregateResource(visits):\n            while i < %d:\n                %s\n                i += 1\n    else:\n        while i < %d:\n            %s\n            i += 1\n    return %s\n", name, setup, start, start+int64(n), update, start+int64(n), update, returned)
				fmt.Fprintf(&cases, "{%s,%d,%d,%v,%d},\n", name, start, n, affine, sign)
				states[name] = state
				index++
			}
		}
	}
	result := compiler.CompileSource("aggregate.ms", source.String(), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if len(regexp.MustCompile(` := -?[0-9]+ - i`).FindAllString(result.Source, -1)) != 2*index {
		t.Fatalf("fixture did not select every aggregate: got %d, want %d\n%s", len(regexp.MustCompile(` := -?[0-9]+ - i`).FindAllString(result.Source, -1)), 2*index, result.Source)
	}
	if strings.Count(result.Source, "rt.CheckCancelled(ctx)") != 2*index {
		t.Fatal("missing or extra query sites")
	}
	generated := strings.Replace(result.Source, "package main", "package main\nimport (\"context\";\"fmt\";\"strings\")", 1)
	generated = strings.Replace(generated, "func main()", "func unusedMain()", 1)
	for name, state := range states {
		start := strings.Index(generated, "func "+name+"(")
		if start < 0 {
			t.Fatal("missing probe")
		}
		end := strings.Index(generated[start+1:], "\nfunc ")
		if end < 0 {
			t.Fatal("missing next declaration")
		}
		end += start + 1
		body := strings.ReplaceAll(generated[start:end], "rt.CheckCancelled(ctx)", "observeAggregate(ctx,i,"+state+")")
		generated = generated[:start] + body + generated[end:]
	}
	generated += `
var queryStates [][2]int
var cancelQuery int
var cancelNow context.CancelFunc
func observeAggregate(ctx *rt.Execution,i,value int) rt.Unit {
 queryStates=append(queryStates,[2]int{i,value})
 if len(queryStates)==cancelQuery {cancelNow()}
 return rt.CheckCancelled(ctx)
}
func main(){
 cases:=[]struct{probe func(*rt.Execution,*rt.List[int],bool)int;start,n int;affine bool;sign int}{
` + cases.String() + `}
 for _,tc:=range cases {for _,mode:=range []string{"cancel","background","nil","shield"} {for _,stop:=range []int{0,1,tc.n/64} {
  base,cancel:=context.WithCancel(context.Background())
  cancelNow=cancel
  ctx:=rt.RootExecution()
  ctx.Context=base
  if mode=="background" {ctx.Context=context.Background()}
  if mode=="nil" {ctx=nil}
  if mode=="shield" {ctx=rt.Shield(ctx)}
  visits:=rt.NewList[int]()
  queryStates=nil
  cancelQuery=stop
  completed:=false
  shouldCancel:=mode=="cancel"&&stop>0
  func(){
   defer func(){if r:=recover();r!=nil {if !shouldCancel || !strings.HasSuffix(fmt.Sprintf("%T",r),".cancelled") {panic(r)}}}()
   want:=3*tc.n
   if tc.affine {want=tc.n*tc.start+tc.n*(tc.n-1)/2}
   want*=tc.sign
   if got:=tc.probe(ctx,visits,ctx!=nil);got!=want {panic("wrong final value")}
   completed=true
  }()
  count:=tc.n/64
  if shouldCancel {count=stop}
  if len(queryStates)!=count {panic("wrong query count")}
  for q,state:=range queryStates {
   offset:=64*(q+1)-1
   value:=3*offset
   if tc.affine {value=offset*tc.start+offset*(offset-1)/2}
   value*=tc.sign
   if state!=[2]int{tc.start+offset,value} {panic("wrong original query state")}
  }
  if completed==shouldCancel {panic("wrong completion")}
  if ctx!=nil {if len(visits.Items)!=1 || visits.Items[0]!=1 {panic("wrong cleanup")}} else if len(visits.Items)!=0 {panic("unexpected cleanup")}
  cancel()
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
		binary := filepath.Join(t.TempDir(), "aggregate")
		if err := build.Build(native, binary); err != nil {
			t.Fatal(err)
		}
		if output, err := commandOutput(t, binary); err != nil {
			t.Fatalf("standalone=%v: %v\n%s", standalone, err, output)
		}
	}
}

func TestCounterAggregateQueryFaultFrame(t *testing.T) {
	result := compiler.CompileSource("aggregate-fault.ms", `fn probe() Int:
    var sum = 0
    var i = 0
    while i < 321:
        sum += i
        i += 1
    return sum
`, compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if !strings.Contains(result.Source, " := 321 - i") {
		t.Fatal("aggregation not selected")
	}
	generated := strings.Replace(result.Source, "package main", "package main\nimport (\"context\";\"fmt\";\"strings\")", 1)
	generated = strings.Replace(generated, "func main()", "func unusedMain()", 1)
	generated += `
 type queryFaultContext struct {context.Context}
 func (queryFaultContext) Err() error {rt.Raise("query fault");return nil}
 func main(){
  defer func(){
   value:=recover()
   fault,ok:=value.(rt.Fault)
   if !ok || fault.Message!="query fault" || strings.Join(fault.Frames,"\n")!="aggregate-fault.ms:4 in probe" {panic(fmt.Sprintf("unexpected query fault: %#v",value))}
  }()
  ctx:=rt.RootExecution()
  ctx.Context=queryFaultContext{context.Background()}
  probe(ctx)
  panic("query did not fault")
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
		binary := filepath.Join(t.TempDir(), "query-fault")
		if err := build.Build(native, binary); err != nil {
			t.Fatal(err)
		}
		if output, err := commandOutput(t, binary); err != nil {
			t.Fatalf("standalone=%v: %v\n%s", standalone, err, output)
		}
	}
}
