interface Value:
    def read() -> Int

impl Value for Int:
    def read() -> Int:
        return 1

impl Value for Missing:
    def read() -> Int:
        return 2

type Box[T]:
    value: T

impl Value for T:
    def read() -> Int:
        return 3
