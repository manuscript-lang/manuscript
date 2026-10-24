# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:145
def incomplete(active: Bool) -> Int:
    if active:
        return 1
    # Rejected: the false path reaches the end without returning Int.
