# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:80 TestExpectedResultGenericInferenceRejects
interface Read:
    def get() -> Int

type Box:
    value: Int

impl Read for Box:
    def get() -> Int: self.value

def first() -> Read: identity(Box(1))
