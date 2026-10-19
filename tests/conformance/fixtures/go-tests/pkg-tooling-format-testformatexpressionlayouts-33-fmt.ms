# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:271 TestFormatExpressionLayouts
fn work() Int:
    if active and allowed and remaining > 0: return 1
    return 0
