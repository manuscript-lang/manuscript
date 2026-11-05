// conform: tags=alternatives,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/build/compiler_test.go:261 TestGenericRecursionAndNamespaceRules
enum First:
    Ready(value: Int)

enum Second:
    Ready(value: Int)

fn wrong() First:
    return Ready(value: 1)
