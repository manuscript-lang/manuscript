// conform: tags=diagnostics,generics,try-result,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
interface Named:
    fn name() String

fn describe[E: Named](item: E) String: item.name()

fn main() Unit:
    _message := describe("missing")
