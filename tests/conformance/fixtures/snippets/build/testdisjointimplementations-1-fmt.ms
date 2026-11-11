// conform: tags=control-flow,formatter,generics,interfaces,lists,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:338 TestDisjointImplementations
interface Read[T]:
    fn get() Int

type Pair[A, B]:
    left: A
    right: B

fn Pair[A, A].get() Int:
    return 1

fn Pair[A, List[A]].get() Int:
    return 2
