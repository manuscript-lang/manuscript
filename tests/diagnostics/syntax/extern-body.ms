// conform: tags=testing,tier-core
// conform: phase=check
extern fn labs(value Int) Int {
    return value
}

export fn main() Int {
    return labs(1)
}
// expect-error: MS1000 3:31-3:32 an extern fn has no body; remove the braces
