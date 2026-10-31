# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:89 TestUnknownTypeDoesNotCascade
fn peek() Missing:
    return 0

fn f() Int:
    match peek():
        x:
            return x
        none:
            return 0
