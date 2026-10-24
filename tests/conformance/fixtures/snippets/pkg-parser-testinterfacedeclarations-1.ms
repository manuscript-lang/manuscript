# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:118 TestInterfaceDeclarations
export interface Read[T: Equal]:
    def get() -> T

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    def get() -> T:
        return self.value
