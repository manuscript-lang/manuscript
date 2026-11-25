// conform: tags=diagnostics
// conform: phase=check

   type queryFaultContext struct {context.Context}
   func (queryFaultContext) Err() error {rt.Raise("query fault");return nil}
   func faultAppend(ctx *rt.Execution,b *rt.StringBuilder,value string) rt.Void {rt.StringBuilder_Freeze(ctx,b);return rt.StringBuilder_Append(ctx,b,value)}
   func main(){
    defer func(){value:=recover();fault,ok:=value.(rt.Fault);if !ok||fault.Message!=
// expect-error: MS1000 5:65-5:66 unexpected source character ';'; Manuscript ends a statement at the end of the line, so remove the semicolon
