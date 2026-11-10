// conform: tags=diagnostics,try-result,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn f() Int!:
    return ok(1)

fn main() Unit:
    let x = f().unwrap()
