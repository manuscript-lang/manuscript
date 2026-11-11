// conform: tags=diagnostics
// conform: phase=check
interface Reader:
    fn read() String
type Box:
    label: String
impl Reader for Box:
    fn read() String:
        return self.label
fn message(value: Reader) String:
    return value.read()
fn make() Box:
    return Box(label: "value")
