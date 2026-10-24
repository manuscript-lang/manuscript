# conform: tags=alternatives,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:261 TestGenericRecursionAndNamespaceRules
type First:
    case Ready(value: Int)

type Second:
    case Ready(value: Int)

def wrong() -> First:
    return Ready(value: 1)
