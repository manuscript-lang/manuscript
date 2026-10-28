# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:283 TestFormatExpressionLayouts
fn work() Int:
    var total = 1
    total += 2
    total *= 3
    box.count -= total
    return total
