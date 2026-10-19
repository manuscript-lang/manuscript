# conform: tags=control-flow,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:35
fn classify(value: Int) String:
    if value < 0:
        return "negative"
    else if value == 0:
        return "zero"
    else:
        return "positive"
