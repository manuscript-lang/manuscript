# conform: tags=control-flow,formatter,parser,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/inspect_determinism_test.go:11 TestInspectionDeterminismAndOriginalSpans
fn one() Int:
    return 1
test "calls":
    if one() != 1:
        return
