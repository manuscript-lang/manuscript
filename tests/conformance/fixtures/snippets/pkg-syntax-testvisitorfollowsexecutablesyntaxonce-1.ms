# conform: tags=closures,control-flow,diagnostics,interfaces,interpolation,match,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/syntax/walk_test.go:12 TestVisitorFollowsExecutableSyntaxOnce
def choose(value: Int) -> Int:
    return value

def collect(fallback: Int = choose(1)) -> String:
    let callbacks = [
        lambda (value: Int = choose(2)) -> Int:
            if value > 0:
                return choose(3)
            else:
                return choose(4)
    ]
    let text = f"{choose(5)}"

    match fallback:
        case _:
            return f"{choose(6)}"

interface Read:
    def read(value: Int) -> Int

type Box:
    value: Int = choose(7)

impl Read for Box:
    def read(value: Int = choose(8)) -> Int:
        return choose(9)
