# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:119 TestFormatExpressionLayouts
fn work() Unit:
    send(
        payload: incoming_request_payload
        .normalize_whitespace()
        .remove_legacy_separators()
        .trim_whitespace()
    )
