# conform: tags=alternatives,closures,control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:33 TestCallArgumentLabelRejections
def one(value: Int) -> Int:
    return value

def two(left: Int, right: Int) -> Int:
    return left - right

def zero() -> Unit:
    return

def identity[T](value: T) -> T:
    return value

def apply(transform: Callable[[Int], Int]) -> Int:
    return transform(1)

type Box:
    value: Int

type Choice:
    case Payload(value: Int)

interface Read:
    def get() -> Int

impl Read for Box:
    def get() -> Int:
        return self.value
