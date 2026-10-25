# conform: tags=closures,diagnostics,faults,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:70
def display_name(
    name: Optional[String],
    create: Callable[[], String]
) -> String:
    return name.get_or_else(create)
