# conform: tags=control-flow,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:95
def display_name(name: Optional[String]) -> String:
    if let value = name:
        return value

    return "Anonymous"
