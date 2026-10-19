# conform: tags=control-flow,diagnostics,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:95
fn display_name(name: Optional[String]) String:
    if let value = name:
        return value
    return "Anonymous"
