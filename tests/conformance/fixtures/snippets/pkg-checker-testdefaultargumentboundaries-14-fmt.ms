# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:27 TestDefaultArgumentBoundaries
interface Add:
    fn add(value: Int) Int

type Offset:
    value: Int

impl Add for Offset:
    fn add(value: Int = self.value) Int:
        return value

fn call(value: Add) Int:
    return value.add()
