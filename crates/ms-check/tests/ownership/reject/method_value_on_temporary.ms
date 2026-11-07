type Counter:
    value: Int

impl Counter:
    var fn bump() Int:
        self.value += 1
        return self.value

fn counter() Counter: Counter(0)

export fn main() Int:
    let pop = [1, 2].pop  // error: must come from a variable
    let bump = counter().bump  // error: must come from a variable
    return bump()
