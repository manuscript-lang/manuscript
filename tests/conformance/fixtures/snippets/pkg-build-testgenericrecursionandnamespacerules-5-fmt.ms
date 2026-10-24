# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:260 TestGenericRecursionAndNamespaceRules
type Data:
    value: Int

impl Equal for Data:
    def compare() -> Unit:
        return
