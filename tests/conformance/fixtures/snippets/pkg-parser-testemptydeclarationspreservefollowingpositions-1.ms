# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/parser/empty_declarations_test.go:49 TestEmptyDeclarationsPreserveFollowingPositions
type Empty: ...

def empty() -> Unit: ...

def kept() -> Int:
    return 3
