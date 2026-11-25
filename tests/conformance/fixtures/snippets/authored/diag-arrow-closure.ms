// conform: tags=diagnostics,tier-core
// conform: phase=check
export fn main() Int {
    doubled := [1, 2].map(x -> x * 2)
    print(doubled)
    return 0
}
// expect-error: MS1000 4:29-4:31 there is no '->' closure; write 'x => x + 1', or 'fn(x Int) Int => x + 1' with explicit types
