// conform: tags=optional,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
export fn main() Int:
    r: Int? := 1
    if r == null:
        return 1

    return 0
