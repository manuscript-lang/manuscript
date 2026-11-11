type R0:
    value: Int

fn R0.read() Int:
    return self.value

fn get0(x: R0) Int:
    return x.read()
