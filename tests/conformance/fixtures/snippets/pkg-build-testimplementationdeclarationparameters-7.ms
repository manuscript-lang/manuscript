# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:548 TestImplementationDeclarationParameters
interface Read:
    def get() -> Int

type Box[T]:
    value: T

impl Read for Box[Int]:
    def get() -> T:
        return self.value
