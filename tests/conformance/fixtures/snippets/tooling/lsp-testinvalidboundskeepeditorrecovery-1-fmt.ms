# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/bound_recovery_test.go:9 TestInvalidBoundsKeepEditorRecovery
interface Named:
    fn name() String

type Box[Named: Named]:
    cause: Named

impl Named for Box[Named]:
    fn name() String: self.cause.name()

type Neighbor:
    value: Int

fn read(item: Neighbor) Int: item.value
