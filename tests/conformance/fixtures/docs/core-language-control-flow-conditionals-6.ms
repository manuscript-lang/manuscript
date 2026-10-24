# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:73
def nonnegative(value: Int) -> Bool:
    if value < 0:
        return False

    return True
