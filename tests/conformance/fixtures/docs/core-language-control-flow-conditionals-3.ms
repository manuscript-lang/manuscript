# conform: tags=control-flow,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:35
def classify(value: Int) -> String:
    if value < 0:
        return "negative"
    elif value == 0:
        return "zero"
    else:
        return "positive"
