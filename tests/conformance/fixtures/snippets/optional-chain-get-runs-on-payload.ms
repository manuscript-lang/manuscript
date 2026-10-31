# conform: tags=optional,diagnostics,tier-core
# conform: phase=check
# conform: origin=thread/type-checker-bug-bash
fn f(x: Int?) Int?:
    return x?.abs().get(0)

export fn main() Int:
    return f(1).get(0)
