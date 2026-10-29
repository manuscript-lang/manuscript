# conform: tags=formatter,match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:474 TestFormatExpressionLayouts
fn choose(value: Choice) Int:
    match value:
        long_variant(
            first_payload_name, second_payload_name, third_payload_name,
            fourth_payload_name
        ): return 1
        _: return 0
