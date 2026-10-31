# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/inference_work_test.go:16 TestDeepGenericArgumentsCheckedOnce
fn identity[T](value: T) T: value

fn first() Int: ...
