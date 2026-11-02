# conform: tags=control-flow,diagnostics,interpolation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:254 TestFormatParagraphs
fn example(value: Int = choose(first: 1, second: 2)) Int:
    let text = "# if value: return {value}"
    let next = choose(
        first: value,
        # Explain this argument.
        second: 2
    )
    if (next > 0 and value > 0): return next

    return 0
