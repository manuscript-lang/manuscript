interface Value:
    fn read() Int

impl Value for Int:
    fn read() Int:
        return 1

impl Value for Missing:
    fn read() Int:
        return 2

type Box[T]:
    value: T

impl Value for T:
    fn read() Int:
        return 3
