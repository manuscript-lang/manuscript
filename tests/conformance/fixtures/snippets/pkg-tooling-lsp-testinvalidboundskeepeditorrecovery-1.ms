# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/bound_recovery_test.go:9 TestInvalidBoundsKeepEditorRecovery
type Box[Error: Error]:
    cause: Error

impl Error for Box[Error]:
    def message() -> String: self.cause.message()

type Neighbor:
    value: Int

def read(item: Neighbor) -> Int: item.value
