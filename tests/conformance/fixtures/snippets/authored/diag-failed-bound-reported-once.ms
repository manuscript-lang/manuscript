# conform: tags=diagnostics,generics,try-result,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
interface Named:
    fn name() String

fn describe[E: Named](item: E) String: item.name()

export fn main() Int:
    let _message = describe("missing")
    return 0
