# conform: tags=closures,diagnostics,faults,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:70
def display_name(name: Optional[String], create: Callable[[], Optional[String]]) -> String:
    return name.or_else(create).get()
