# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:238 TestFormatExpressionLayouts
fn work() Unit:
    send(
        destination: resolve(name: service, region: region),
        payload: encode(build(records))
    )
