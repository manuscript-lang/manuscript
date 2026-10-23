# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:353 TestFormatExpressionLayouts
fn work() String:
    return (
        incoming_request_payload
        .normalize_whitespace()
        .replace(old: legacy_separator, new: current_separator)
        .trim()
    )
