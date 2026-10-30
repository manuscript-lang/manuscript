# conform: tags=control-flow,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:77
fn greet(name: String?) String:
    if let value = name:
        return "Hello, " + value

    return "Hello!"
