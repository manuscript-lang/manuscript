# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:260 TestGenericRecursionAndNamespaceRules
type Data:
    value: Int

impl Equal for Data:
    fn compare() Unit:
        return
