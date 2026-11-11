// conform: tags=diagnostics
// conform: phase=check
interface Crash:
    fn run() Int
type Item:
    value: Int
impl Crash for Item:
    fn run() Int:
        return 1 / self.value
export fn main() Int:
    item := Item(0)
    run := item.run
    return run()
