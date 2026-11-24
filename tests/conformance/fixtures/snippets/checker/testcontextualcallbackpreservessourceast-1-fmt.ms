// conform: tags=closures,formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/checker_test.go:55 TestContextualCallbackPreservesSourceAST
type Callback:
    value fn(Int) Int

fn example() Void:
    _callback := Callback(value => value + 1)
