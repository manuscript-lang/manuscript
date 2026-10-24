# conform: tags=closures,faults,formatter,generics,lists,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/checker/inference_hints_test.go:45 TestUnknownTypeDoesNotCascadeIntoInference
def collect[T, U](
    items: List[T],
    step: Callable[[T], Result[List[U], MissingError]]
) -> Result[List[U], MissingError]:
    return step(items.get(0))

def first() -> Unit:
    let result = collect(
        items: [1, 2],
        step: lambda (value: Int) -> Result[List[Int], MissingError]: ok(
            [value]
        )
    )
    let unrelated: Int = "wrong"
