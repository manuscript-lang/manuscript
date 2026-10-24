# conform: tags=control-flow,formatter,generics,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:118 TestInterfaceDeclarations
export interface Read[T: Equal]:
    def get() -> ref T

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    def get() -> ref T:
        return self.value
