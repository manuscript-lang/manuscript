# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/grammar.md:203
def double(value: Int) -> Int: value * 2

def positive(value: Int) -> Bool:
    if value > 0: return True
    else: return False
