# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:118 TestSourceContractsFieldsAndTypeRename
interface Reader:
    fn read() String

type Box:
    label: String

impl Reader for Box:
    fn read() String:
        return self.label.clone()

fn message(value: Reader) String:
    return value.read()

fn make() Box:
    return Box(label: "value")
