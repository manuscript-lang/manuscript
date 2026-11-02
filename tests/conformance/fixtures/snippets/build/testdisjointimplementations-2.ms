# conform: tags=closures,control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:350 TestDisjointImplementations
interface Read:
    fn get() Int

type Box[T]:
    value: T

impl Read for Box[fn(Int) Int]:
    fn get() Int:
        return 1

impl Read for Box[fn(Int) Int]:
    fn get() Int:
        return 2
