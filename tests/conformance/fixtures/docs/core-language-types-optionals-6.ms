# conform: tags=control-flow,diagnostics,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:77
def greet(name: Optional[String]) -> String:
    if let value = name:
        return "Hello, " + value

    return "Hello!"
