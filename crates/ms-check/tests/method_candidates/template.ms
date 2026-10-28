type R0:
    value: Int

impl R0:
    def read() -> Int:
        return self.value

def get0(x: R0) -> Int:
    return x.read()
