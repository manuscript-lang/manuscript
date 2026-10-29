# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/conditionals.md:73
fn nonnegative(value: Int) Bool:
    if value < 0:
        return false

    return true
