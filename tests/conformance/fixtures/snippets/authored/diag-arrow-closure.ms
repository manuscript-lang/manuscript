// conform: tags=diagnostics,tier-core
// conform: phase=check
export fn main() Int:
    doubled := [1, 2].map(x -> x * 2)
    print(doubled)
    return 0
