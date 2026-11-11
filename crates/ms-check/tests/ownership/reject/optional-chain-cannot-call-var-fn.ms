type Counter:
    n: Int

fn var Counter.bump() Int:
    self.n += 1
    return self.n

fn bump_if_present(c: Counter?) Int?:
    return c?.bump() // error: parameter `c` is not declared var

fn bump_let() Int?:
    c: Counter? := Counter(1)
    return c?.bump() // error: is an immutable binding

fn bump_view(m: Map[String, Counter]) Int?:
    return m.get("a")?.bump() // error: on a value that is not a variable
