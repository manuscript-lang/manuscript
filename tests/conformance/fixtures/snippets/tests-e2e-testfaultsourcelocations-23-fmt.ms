# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:177 TestFaultSourceLocations
interface Crash:
    def run() -> Int

type Item:
    value: Int

impl Crash for Item:
    def run() -> Int:
        return 1 / self.value

export def main() -> Int:
    let item = Item(0)
    let run = item.run
    return run()
