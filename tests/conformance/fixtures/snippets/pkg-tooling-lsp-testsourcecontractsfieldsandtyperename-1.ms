# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:118 TestSourceContractsFieldsAndTypeRename
interface Reader:
    fn read() ref String

type Box:
    label: String

impl Reader for Box:
    fn read() ref String:
        return self.label

fn message(value: Reader) ref String:
    return value.read()

fn make() Box:
    return Box(label: "value")
