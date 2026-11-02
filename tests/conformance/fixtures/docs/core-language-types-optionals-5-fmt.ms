# conform: tags=closures,faults,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:70
fn display_name(name: String?, create: fn() String) String:
    return name.get_or_else(create)
