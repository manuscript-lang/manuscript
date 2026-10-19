# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:128 TestFormatParagraphs
fn choose(value: Choice) Int:
    match value:
        first: return 1
        second: return 2
        third:
            let result = calculate()
            return result
        _: return 0
    return 3
