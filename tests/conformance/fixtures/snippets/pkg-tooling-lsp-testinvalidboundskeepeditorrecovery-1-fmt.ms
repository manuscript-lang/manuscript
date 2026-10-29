# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/bound_recovery_test.go:9 TestInvalidBoundsKeepEditorRecovery
type Box[Error: Error]:
    cause: Error

impl Error for Box[Error]:
    fn message() String: self.cause.message()

type Neighbor:
    value: Int

fn read(item: Neighbor) Int: item.value
