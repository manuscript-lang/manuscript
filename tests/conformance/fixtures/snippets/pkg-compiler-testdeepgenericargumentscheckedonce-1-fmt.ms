# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/inference_work_test.go:16 TestDeepGenericArgumentsCheckedOnce
def identity[T](value: T) -> T: value

def first() -> Int: ...
