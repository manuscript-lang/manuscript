# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_layout_test.go:235 TestFormatExpressionLayouts
fn work() Unit:
    send(
        destination: resolve(name: service, region: region),
        payload: encode(build(records))
    )
