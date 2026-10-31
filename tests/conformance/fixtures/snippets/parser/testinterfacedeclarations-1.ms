# conform: tags=control-flow,diagnostics,generics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:118 TestInterfaceDeclarations
export interface Read[T: Equal]:
    fn get() T

type Box[T: Clonable]:
    value: T

impl Read[T] for Box[T]:
    fn get() T:
        return self.value.clone()
