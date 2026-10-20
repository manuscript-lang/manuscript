# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:500 TestFormatExpressionLayouts
fn work() Int:
    if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic":
        return 1
    return 0
