# conform: tags=control-flow,formatter,generics,interfaces,lists,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:338 TestDisjointImplementations
interface Read[T]:
    def get() -> Int

type Pair[A, B]:
    left: A
    right: B

impl Read[A] for Pair[A, A]:
    def get() -> Int:
        return 1

impl Read[A] for Pair[A, List[A]]:
    def get() -> Int:
        return 2
