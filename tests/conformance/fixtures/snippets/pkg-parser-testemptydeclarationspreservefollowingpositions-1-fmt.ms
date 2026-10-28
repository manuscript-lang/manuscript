# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/empty_declarations_test.go:49 TestEmptyDeclarationsPreserveFollowingPositions
type Empty: ...

fn empty() Unit: ...

fn kept() Int:
    return 3
