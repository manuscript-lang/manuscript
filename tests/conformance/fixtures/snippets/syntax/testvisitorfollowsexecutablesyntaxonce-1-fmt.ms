# conform: tags=closures,control-flow,formatter,interfaces,interpolation,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/syntax/walk_test.go:12 TestVisitorFollowsExecutableSyntaxOnce
fn choose(value: Int) Int:
    return value

fn collect(fallback: Int = choose(1)) String:
    let _callbacks = [
        fn(value: Int = choose(2)) Int:
            if value > 0:
                return choose(3)
            else:
                return choose(4)
    ]
    let _text = "{choose(5)}"

    match fallback:
        _:
            return "{choose(6)}"

interface Read:
    fn read(value: Int) Int

type Box:
    value: Int = choose(7)

impl Read for Box:
    fn read(value: Int = choose(8)) Int:
        return choose(9)
