// conform: tags=control-flow,interfaces,records,tier-core
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:177 TestFaultSourceLocations
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
