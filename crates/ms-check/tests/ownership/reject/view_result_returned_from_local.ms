def make() -> String:
    return "  a  "

def f() -> String:
    let line = make()
    return line.trim()  # error: `trim` borrows its result from `line`
