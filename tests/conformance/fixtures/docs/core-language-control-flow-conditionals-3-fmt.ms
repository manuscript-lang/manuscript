# conform: tags=control-flow,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/conditionals.md:35
def classify(value: Int) -> String:
    if value < 0:
        return "negative"
    elif value == 0:
        return "zero"
    else:
        return "positive"
