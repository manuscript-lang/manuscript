// conform: tags=diagnostics
// conform: phase=check

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
 