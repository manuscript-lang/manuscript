// conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:177 TestFaultSourceLocations
interface Crash:
    fn run() Int

type Item:
    value: Int

fn Item.run() Int:
    return 1 / self.value

export fn main() Int:
    item := Item(0)
    run := item.run
    return run()
