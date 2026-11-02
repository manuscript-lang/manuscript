# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:448 TestFormatExpressionLayouts
fn work(value: Bool = active and allowed and remaining > 0) Bool: return value
