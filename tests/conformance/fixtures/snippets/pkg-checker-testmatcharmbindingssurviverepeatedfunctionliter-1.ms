# conform: tags=closures,diagnostics,generics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/optional_test.go:34 TestMatchArmBindingsSurviveRepeatedFunctionLiteralChecks
fn call[T](operation: fn() T) T:
    return operation()

fn get() Result[Int, Error]: return ok(value: 1)

fn note() Unit: return unit

fn run() Unit:
    call(
        operation: fn() Int:
            match get():
                ok(_n): note()
                error(_e): note()

            return 0
    )
