fn make() String:
    return "  a  "

fn f() String:
    let line = make()
    return line.trim()  # error: `trim` borrows its result from `line`
