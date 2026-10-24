export interface Read:
    def read() -> Int

export type Reader:
    operation: Callable[[], Int]

export def invoke[T: Read](value: T) -> Int: value.read()
