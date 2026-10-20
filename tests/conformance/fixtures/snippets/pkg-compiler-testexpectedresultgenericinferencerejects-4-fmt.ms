# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/contextual_generics_test.go:93 TestExpectedResultGenericInferenceRejects
fn required(value: Int) Int: value
fn first() Unit:
    var callback: fn(value: Int) Int = from_callback(fn(): fn(value: Int = 4): value)
    callback = required
    callback()
