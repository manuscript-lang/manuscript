# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/grammar.md:203
fn double(value: Int) Int: value * 2
fn positive(value: Int) Bool:
    if value > 0: return true
    else: return false
