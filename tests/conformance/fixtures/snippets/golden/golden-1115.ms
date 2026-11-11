// conform: tags=diagnostics
// conform: phase=check
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
