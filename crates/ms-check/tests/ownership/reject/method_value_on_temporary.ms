type Counter:
    value: Int

fn var Counter.bump() Int:
    self.value += 1
    return self.value

fn counter() Counter: Counter(0)

export fn main() Int:
    pop := [1, 2].pop  // error: must come from a variable
    bump := counter().bump  // error: must come from a variable
    return bump()
