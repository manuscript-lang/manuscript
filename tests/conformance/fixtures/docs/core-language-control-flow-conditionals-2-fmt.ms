# conform: tags=control-flow,formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/conditionals.md:20
fn status(active: Bool) String:
    if active: return "Active"
    else: return "Inactive"
