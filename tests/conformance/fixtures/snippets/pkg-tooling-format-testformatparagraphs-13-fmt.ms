# conform: tags=closures,control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:199 TestFormatParagraphs
def example() -> Int:
    let result = apply(
        value: 3,
        transform: (
            lambda (value: Int) -> Int:
                if value == 0: return 0

                let next = value + 1
                return next
        )
    )

    return result
