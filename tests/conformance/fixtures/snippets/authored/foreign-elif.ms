# conform: tags=diagnostics,parser,tier-core
# conform: phase=parse
# conform: origin=foreign-syntax diagnostics
fn f(x: Int) Int:
    if x > 0:
        return 1
    elif x < 0:
        return 2
    return 0
