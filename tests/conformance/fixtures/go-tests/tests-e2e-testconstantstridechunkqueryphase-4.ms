# conform: tags=control-flow,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/counter_chunk_test.go:44 TestConstantStrideChunkQueryPhase

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
