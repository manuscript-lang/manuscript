# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:271 TestFormatExpressionLayouts
def work() -> Int:
    if active and allowed and remaining > 0: return 1

    return 0
