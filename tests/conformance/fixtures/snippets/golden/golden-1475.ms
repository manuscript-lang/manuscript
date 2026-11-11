// conform: tags=diagnostics
// conform: phase=check
export fn main() Int:
    crash := fn() Int:
        return 1 / 0
    return crash()
