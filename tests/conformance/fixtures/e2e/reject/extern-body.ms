// conform: tags=testing,tier-core
// conform: phase=check
extern fn labs(value: Int) Int:
    return value

export fn main() Int:
    return labs(1)
