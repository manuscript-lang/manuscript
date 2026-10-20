# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/syntax/walk_test.go:68 TestVisitorIncludesAssignmentTargetBeforeValue
fn update() Unit:
    owner().value = replacement()
