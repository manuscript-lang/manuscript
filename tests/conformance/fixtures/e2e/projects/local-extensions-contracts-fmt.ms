# conform: tags=faults,formatter,generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/local_extensions/contracts.ms
export interface Read[T]:
    def get() -> T

export def invoke[T: Read[Int]](value: T) -> Int:
    return value.get()

export def relay[T: Read[Int]](value: T) -> Int:
    return invoke(value)

export def as_view[T: Read[Int]](value: T) -> Read[Int]:
    return value

export def read_view(value: Read[Int]) -> Int:
    return value.get()
