# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/contextual_inference_test.go:46 TestExpectedFunctionResultErasesDefaultPermissions
fn from_callback[T](factory: fn() T) T: factory()

fn first() Unit:
    let _callback: fn(Int) Int = from_callback(fn: fn(value: Int = 4): value)
