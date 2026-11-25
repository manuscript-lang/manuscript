// conform: tags=diagnostics,tier-core
// conform: phase=check
type Counter {
    n Int
}

var fn Counter.inc() Void {
    self.n += 1
}

export fn main() Int {
    return 0
}
// expect-error: MS1000 7:1-7:7 a method that changes its receiver is written fn var Type.name(), with var after fn
// expect-fix: 7:1-7:7 "fn var"
