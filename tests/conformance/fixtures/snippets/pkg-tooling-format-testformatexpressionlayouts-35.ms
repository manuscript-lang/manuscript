# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:283 TestFormatExpressionLayouts
def work() -> Int:
    var total = 1
    total += 2
    total *= 3
    box.count -= total
    return total
