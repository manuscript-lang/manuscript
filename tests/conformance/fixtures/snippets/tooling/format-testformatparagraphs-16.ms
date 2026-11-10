// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:240 TestFormatParagraphs
// File introduction.
fn example() Int:
    first := 1

    // A deliberate new step.
    second := first + 1
    if second > 2:
        run(second)
        // A comment inside the branch.

    // A comment on the next step.
    return second
