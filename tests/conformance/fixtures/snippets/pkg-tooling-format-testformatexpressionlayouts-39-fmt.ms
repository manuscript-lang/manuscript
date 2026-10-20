# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:309 TestFormatExpressionLayouts
fn work() Unit:
    send(condition: active and allowed and remaining > 0, payload: "data")
