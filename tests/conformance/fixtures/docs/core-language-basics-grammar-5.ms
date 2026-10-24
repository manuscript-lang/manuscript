# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/grammar.md:203
def double(value: Int) -> Int: value * 2

def positive(value: Int) -> Bool:
    if value > 0: return True
    else: return False
