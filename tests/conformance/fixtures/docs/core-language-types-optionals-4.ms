# conform: tags=diagnostics,faults,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:63
def display_name(name: Optional[String]) -> ref String:
    return name.get("Anonymous")
