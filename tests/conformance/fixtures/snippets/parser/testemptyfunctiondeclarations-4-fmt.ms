# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:14 TestEmptyFunctionDeclarations
type Counter:
    value: Int

impl Counter:
    fn double() Int:
        return self.value * 2
