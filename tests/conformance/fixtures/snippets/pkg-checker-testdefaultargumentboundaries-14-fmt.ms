# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:27 TestDefaultArgumentBoundaries
interface Add:
    def add(value: Int) -> Int

type Offset:
    value: Int

impl Add for Offset:
    def add(value: Int = self.value) -> Int:
        return value

def call(value: Add) -> Int:
    return value.add()
