# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:89 TestUnknownTypeDoesNotCascade
fn peek() Missing:
    return 0

fn f() Int:
    match peek():
        some(x):
            return x
        none:
            return 0
