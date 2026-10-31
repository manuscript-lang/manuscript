# conform: tags=control-flow,diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:20
fn status(active: Bool) String:
    if active: return "Active"
    else: return "Inactive"
