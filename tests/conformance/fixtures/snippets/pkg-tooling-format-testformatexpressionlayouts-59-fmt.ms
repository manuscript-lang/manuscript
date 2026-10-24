# conform: tags=closures,formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:435 TestFormatExpressionLayouts
def work() -> Bool:
    return (
        [[1, 2], [3]].flat_map(
            transform: lambda (value: List[Int]) -> List[Int]: return value
        ) == [1, 2, 3]
    )
