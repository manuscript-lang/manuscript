interface Divide:
    def divide(value: Int) -> Int

type Number:
    value: Int

impl Divide for Number:
    def divide(value: Int = 1 / self.value) -> Int:
        return value

export def main() -> Int:
    return Number(0).divide()
