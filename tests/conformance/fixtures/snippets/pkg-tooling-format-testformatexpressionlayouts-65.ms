# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:469 TestFormatExpressionLayouts
def choose(value: Choice) -> Int:
    match value:
        case long_variant(
            first_payload_name, second_payload_name, third_payload_name,
            fourth_payload_name
        ): return 1
        case _: return 0
