# conform: tags=closures,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/checker_test.go:55 TestContextualCallbackPreservesSourceAST
type Callback:
    value: fn(Int) Int

fn example() Unit:
    let _callback = Callback(fn value: value + 1)
