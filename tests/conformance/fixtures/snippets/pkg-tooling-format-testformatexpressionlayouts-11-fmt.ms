# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:116 TestFormatExpressionLayouts
def work() -> Unit:
    send(
        payload: incoming_request_payload
        .normalize_whitespace()
        .remove_legacy_separators()
        .trim_whitespace()
    )
