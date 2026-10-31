# conform: tags=alternatives,closures,control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:33 TestCallArgumentLabelRejections
fn one(value: Int) Int:
    return value

fn two(left: Int, right: Int) Int:
    return left - right

fn zero() Unit:
    return

fn identity[T](value: T) T:
    return value

fn apply(transform: fn(Int) Int) Int:
    return transform(1)

type Box:
    value: Int

type Choice:
    case Payload(value: Int)

interface Read:
    fn get() Int

impl Read for Box:
    fn get() Int:
        return self.value
