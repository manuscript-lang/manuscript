# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:138 TestFormatParagraphs
def choose(value: Choice) -> Int:
    match value:
        case first: return 1
        case second: return 2
        case third:
            let result = calculate()
            return result
        case _: return 0

    return 3
