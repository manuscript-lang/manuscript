# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/format/format_paragraphs_test.go:240 TestFormatParagraphs
# File introduction.
fn example() Int:
    let first = 1
    # A deliberate new step.
    let second = first + 1
    if second > 2:
        run(second)
        # A comment inside the branch.
    # A comment on the next step.
    return second
