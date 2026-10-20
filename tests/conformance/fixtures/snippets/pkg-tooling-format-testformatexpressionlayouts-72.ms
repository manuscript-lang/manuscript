# conform: tags=control-flow,diagnostics,interpolation,strings,tier-core,with-cleanup
# conform: phase=check
# conform: origin=pkg/tooling/format/format_layout_test.go:523 TestFormatExpressionLayouts
fn work() String:
    let values = [1, 2, 3]
    let text = "# A deliberately long literal with {format(value: "nested text")} that must retain its exact original spelling."
    if enabled: return text

    return text
