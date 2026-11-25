// conform: tags=diagnostics
// conform: phase=check
fn f(first Int = 1, second Int = 2, third Int = 3) Int => first

fn run(first Int, second Int, third Int) Int { ... }
// expect-error: MS3000 5:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
