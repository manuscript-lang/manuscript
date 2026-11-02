# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/syntax/walk_test.go:68 TestVisitorIncludesAssignmentTargetBeforeValue
fn update() Unit:
    owner().value = replacement()
