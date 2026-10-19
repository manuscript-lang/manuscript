# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:145
fn incomplete(active: Bool) Int:
    if active:
        return 1
    # Rejected: the false path reaches the end without returning Int.
