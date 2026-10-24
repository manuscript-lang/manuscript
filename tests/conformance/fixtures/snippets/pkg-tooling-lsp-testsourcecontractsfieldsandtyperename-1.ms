# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:118 TestSourceContractsFieldsAndTypeRename
interface Reader:
    def read() -> String

type Box:
    label: String

impl Reader for Box:
    def read() -> String:
        return self.label

def message(value: Reader) -> String:
    return value.read()

def make() -> Box:
    return Box(label: "value")
