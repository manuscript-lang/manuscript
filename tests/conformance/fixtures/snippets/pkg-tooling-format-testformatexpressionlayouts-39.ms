# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:309 TestFormatExpressionLayouts
def work() -> Unit:
    send(condition: active and allowed and remaining > 0, payload: "data")
