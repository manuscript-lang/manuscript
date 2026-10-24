# conform: tags=faults,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:63
def display_name(name: Optional[String]) -> ref String:
    return name.get("Anonymous")
