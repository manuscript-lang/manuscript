type Logger:
    n: Int

impl Logger:
    fn info() Unit: print("info")
    fn quiet() Int: self.n

fn stored_method() Unit:
    log := Logger(1)
    f := log.info
    f()

fn pure_method() Int:
    log := Logger(1)
    f := log.quiet
    return f()

export fn main() Int:
    stored_method()
    return pure_method()
