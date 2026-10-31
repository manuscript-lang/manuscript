# conform: tags=faults,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:63
fn display_name(name: String?) String:
    return name.get("Anonymous")
