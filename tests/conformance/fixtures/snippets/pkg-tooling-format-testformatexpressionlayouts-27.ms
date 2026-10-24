# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:235 TestFormatExpressionLayouts
def work() -> Unit:
    send(
        destination: resolve(name: service, region: region),
        payload: encode(build(records))
    )
