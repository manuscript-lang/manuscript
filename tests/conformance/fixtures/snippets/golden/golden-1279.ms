// conform: tags=diagnostics
// conform: phase=check
// α😀
interface Read:
    fn get() Int
type Box:
    value: Int // 😀é
impl Read for Box:
    fn get() Int:
        return self.value
fn neighbor() Int: 1
