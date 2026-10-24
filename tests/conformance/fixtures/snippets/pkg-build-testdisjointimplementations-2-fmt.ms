# conform: tags=closures,control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:350 TestDisjointImplementations
interface Read:
    def get() -> Int

type Box[T]:
    value: T

impl Read for Box[Callable[[Int], Int]]:
    def get() -> Int:
        return 1

impl Read for Box[Callable[[Int], Int]]:
    def get() -> Int:
        return 2
