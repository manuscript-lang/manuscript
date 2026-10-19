# conform: tags=control-flow,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/counter_aggregate_test.go:97 TestCounterAggregateQueryStates

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
