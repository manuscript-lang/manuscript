// conform: tags=functions,tier-core
// conform: phase=run
// Two functions that call each other share one recursion check; the answers do not change.
fn count(n: Int) Int:
    if n < 2:
        return 1
    return pair(n) + 1

fn pair(n: Int) Int:
    return count(n - 1) + count(n - 2)

fn is_even(n: Int) Bool:
    if n == 0:
        return true
    return is_odd(n - 1)

fn is_odd(n: Int) Bool:
    if n == 0:
        return false
    return is_even(n - 1)

fn main() Unit:
    print("{count(20)} {is_even(10)} {is_even(7)} {is_odd(7)}")
