# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/group_test.go:65 TestBindingGroupRejections
fn main() Unit:
    if true: let (
        a = 1
    )
