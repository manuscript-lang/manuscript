# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:548 TestImplementationDeclarationParameters
interface Read:
    def get() -> Int

type Box[T]:
    value: T

impl Read for Box[Int]:
    def get() -> T:
        return self.value
