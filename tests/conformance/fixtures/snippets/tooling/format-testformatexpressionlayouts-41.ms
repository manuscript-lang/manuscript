# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:318 TestFormatExpressionLayouts
fn work() Bool:
    return active or allowed and remaining > 0
