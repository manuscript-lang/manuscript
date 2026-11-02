# conform: tags=closures,diagnostics,faults,generics,lists,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/checker/inference_hints_test.go:45 TestUnknownTypeDoesNotCascadeIntoInference
fn collect[T, U](items: List[T], step: fn(T) List[U]!MissingError) List[U]!MissingError:
    return step(items.get(0))

fn first() Unit:
    let result = collect(
        items: [1, 2], step: fn(value: Int) List[Int]!MissingError: ok([value])
    )
    let unrelated: Int = "wrong"
