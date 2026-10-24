# conform: tags=diagnostics,interpolation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_test.go:190 TestFormatMapAndShorthand
def f() -> Unit:
    let values = {"a": 1, "b": {1: 2}}
    consume(values, other: {})
