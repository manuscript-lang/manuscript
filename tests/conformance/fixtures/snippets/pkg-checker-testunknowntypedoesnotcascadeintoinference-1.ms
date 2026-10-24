# conform: tags=closures,diagnostics,faults,generics,lists,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:45 TestUnknownTypeDoesNotCascadeIntoInference
def collect[T, U](
    items: List[T],
    step: Callable[[T], Result[List[U], MissingError]]
) -> Result[List[U], MissingError]:
    return step(items.get(0))

def first() -> Unit:
    let result = collect(
        items: [1, 2], step: lambda (value: Int) -> Result[List[Int], MissingError]: ok([value])
    )
    let unrelated: Int = "wrong"
