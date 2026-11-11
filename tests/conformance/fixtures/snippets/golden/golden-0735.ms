// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
impl Read for E1:
    fn get() Int: self.code
fn read[T](r: Result[T, Read]) Unit: return
fn first() Unit: read(f())