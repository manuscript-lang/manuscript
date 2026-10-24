# conform: tags=diagnostics,sets,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:16 TestRecursiveTypesPreserveInitializationAndHashing
def f(values: Set[Node]) -> Unit: return
