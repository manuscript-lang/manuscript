# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:260 TestFormatExpressionLayouts
fn work() Unit:
    let _larger = [1, 2, 3, 4, 5]
    let _nested = [[1, 2], [3, 4]]
