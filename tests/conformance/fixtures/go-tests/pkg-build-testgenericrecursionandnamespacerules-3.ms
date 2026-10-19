# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:258 TestGenericRecursionAndNamespaceRules
type Box[Int]:
    value: Int
