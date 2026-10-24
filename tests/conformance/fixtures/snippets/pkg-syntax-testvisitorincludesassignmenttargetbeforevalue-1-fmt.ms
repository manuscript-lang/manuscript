# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/syntax/walk_test.go:68 TestVisitorIncludesAssignmentTargetBeforeValue
def update() -> Unit:
    owner().value = replacement()
