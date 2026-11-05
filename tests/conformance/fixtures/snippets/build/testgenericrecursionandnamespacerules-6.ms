// conform: tags=alternatives,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:261 TestGenericRecursionAndNamespaceRules
enum First:
    Ready(value: Int)

enum Second:
    Ready(value: Int)

fn wrong() First:
    return Ready(value: 1)
