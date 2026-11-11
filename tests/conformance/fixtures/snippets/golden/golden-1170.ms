// conform: tags=diagnostics
// conform: phase=check
type Box[Error: Error]:
    cause: Error
impl Error for Box[Error]:
    fn message() String: self.cause.message()
type Neighbor:
    value: Int
fn read(item: Neighbor) Int: item.value
