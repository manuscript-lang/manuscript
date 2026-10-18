package e2e_test

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"math"
	"path/filepath"
	"strings"
	"testing"
)

// Observe the actual emitted query sites without adding effects to the source
// loop. The callback records both original locals before asking the real runtime
// to cancel, so phase, partial chunks and cleanup are all checked natively.
func TestConstantStrideChunkQueryPhase(t *testing.T) {
	var source strings.Builder
	source.WriteString(`import Closeable from "@std/cleanup.ms"
type Resource:
    visits: List[Int]
impl Closeable for Resource:
    fn close() Unit:
        self.visits.append(1)
`)
	var cases strings.Builder
	index := 0
	for _, n := range []int{256, 257, 319, 320, 321} {
		for _, start := range []int64{0, -1000, math.MinInt64, math.MaxInt64 - int64(n)} {
			fmt.Fprintf(&source, "fn probe%d(visits: List[Int]) Int:\n    var sum = 0\n    var i = %d\n    with resource = Resource(visits):\n        while i < %d:\n            sum += 3\n            i += 1\n    return sum\n", index, start, start+int64(n))
			fmt.Fprintf(&cases, "{probe%d, %d, %d},\n", index, start, n)
			index++
		}
	}
	result := compiler.CompileSource("chunks.ms", source.String(), compiler.Options{})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	if got := strings.Count(result.Source, "rt.CheckCancelled(ctx)"); got != index {
		t.Fatalf("query sites=%d want %d", got, index)
	}
	generated := strings.Replace(result.Source, "package main", "package main\nimport \"context\"", 1)
	generated = strings.Replace(generated, "func main()", "func unusedMain()", 1)
	generated = strings.ReplaceAll(generated, "rt.CheckCancelled(ctx)", "observePoll(ctx, i, sum)")
	generated += `
var queries [][2]int
var cancelQuery int
var cancelNow context.CancelFunc
func observePoll(ctx *rt.Execution, i, sum int) rt.Unit {
 queries=append(queries,[2]int{i,sum})
 if len(queries)==cancelQuery {cancelNow()}
 return rt.CheckCancelled(ctx)
}
func main() {
 cases:=[]struct{probe func(*rt.Execution,*rt.List[int])int; start,n int}{
` + cases.String() + `}
 for _, tc:=range cases {
  for _, stop:=range []int{0,1,tc.n/64} {
   ctx:=rt.RootExecution()
   ctx.Context,cancelNow=context.WithCancel(context.Background())
   visits:=rt.NewList[int]()
   queries=nil
   cancelQuery=stop
   completed:=false
   func(){
    defer func(){if r:=recover();r!=nil && ctx.Context.Err()==nil {panic(r)}}()
    if got:=tc.probe(ctx,visits);got!=3*tc.n {panic("wrong normal result")}
    completed=true
   }()
   count:=tc.n/64
   if stop>0 {count=stop}
   if len(queries)!=count {panic("wrong query count")}
   for q, state:=range queries {
    offset:=64*(q+1)-1
    if state!=[2]int{tc.start+offset,3*offset} {panic("wrong original query state")}
   }
   if completed!=(stop==0) {panic("wrong cancellation result")}
   if len(visits.Items)!=1 || visits.Items[0]!=1 {panic("cleanup skipped or repeated")}
   cancelNow()
  }
 }
}
`
	// Exercise both separate and standalone runtime linkage with identical code.
	for _, standalone := range []bool{false, true} {
		native := generated
		if standalone {
			var err error
			native, err = build.Standalone(native)
			if err != nil {
				t.Fatal(err)
			}
		}
		binary := filepath.Join(t.TempDir(), "chunks")
		if err := build.Build(native, binary); err != nil {
			t.Fatal(err)
		}
		if output, err := commandOutput(t, binary); err != nil {
			t.Fatalf("standalone=%v: %v\n%s", standalone, err, output)
		}
	}
}
