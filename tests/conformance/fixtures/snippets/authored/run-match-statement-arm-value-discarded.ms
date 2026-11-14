// conform: tags=match,tier-core
// conform: phase=run
// A match used as a statement may end an arm in a call that returns a value; the value is dropped.
enum Step:
    Show(text: String)
    Count(n: Int)
    Check(n: Int)

fn double(n: Int) Int:
    return n * 2

fn checked(n: Int) Int!:
    return ok(n + 1)

fn run(step: Step) Unit!:
    match step:
        Show(text):
            print(text)
        Count(n):
            double(n)
        Check(n):
            checked(n)?
    return ok(unit)

export fn main() Int:
    for step in [Step.Show("shown"), Step.Count(2), Step.Check(3)]:
        r := run(step)
        print("{r.is_ok()}")
    return 0
