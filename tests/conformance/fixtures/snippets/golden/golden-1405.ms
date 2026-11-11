// conform: tags=diagnostics
// conform: phase=check

   type queryFaultContext struct {context.Context}
   func (queryFaultContext) Err() error {rt.Raise("query fault");return nil}
   func faultAppend(ctx *rt.Execution,b *rt.StringBuilder,value string) rt.Unit {rt.StringBuilder_Freeze(ctx,b);return rt.StringBuilder_Append(ctx,b,value)}
   func main(){
    defer func(){value:=recover();fault,ok:=value.(rt.Fault);if !ok||fault.Message!=