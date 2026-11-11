// conform: tags=diagnostics
// conform: phase=check
interface Add:
    fn add(value: Int) Int
type Offset:
    value: Int
impl Add for Offset:
    fn add(value: Int = self.value) Int:
        return value
fn call(value: Add) Int:
    return value.add()
