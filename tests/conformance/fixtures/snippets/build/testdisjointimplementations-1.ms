# conform: tags=control-flow,diagnostics,generics,interfaces,lists,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:338 TestDisjointImplementations
interface Read[T]:
    fn get() Int

type Pair[A, B]:
    left: A
    right: B

impl Read[A] for Pair[A, A]:
    fn get() Int:
        return 1

impl Read[A] for Pair[A, List[A]]:
    fn get() Int:
        return 2
