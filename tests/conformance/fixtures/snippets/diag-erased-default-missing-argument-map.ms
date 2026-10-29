# conform: tags=diagnostics,closures,functions,tier-core
# conform: phase=check
# conform: origin=ms-build/tests/callable_defaults.rs
fn original(value: Int = 7) Int: value + 1

fn replacement(value: Int) Int: value + 2

export fn main() Int:
    let callbacks = {"known": original, "unknown": replacement}
    return callbacks["unknown"]()
