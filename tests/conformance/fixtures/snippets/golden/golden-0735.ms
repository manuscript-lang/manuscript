// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
impl Read for E1:
    fn get() Int => self.code
fn read[T](r: Result[T, Read]) Void => return
fn first() Void => read(f())