# conform: tags=control-flow,diagnostics,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/control-flow/conditionals.md:51
fn greeting(name: String?) String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"
