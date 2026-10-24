# conform: tags=closures,control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:142 TestFormatExpressionLayouts
def work() -> Int:
    if let value = (
        [2, 5, 3, (-6), (-9), 1, 2, 3, 4]
        .clone()
        .sorted(lambda (l: Int, r: Int) -> Int: (l - r))
        .first()
    ):
        return value

    return 0
