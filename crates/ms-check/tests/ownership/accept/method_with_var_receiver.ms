type Counter:
    values: List[Int]

impl Counter:
    var def bump() -> Unit:
        self.values.append(1)

    def size() -> Int:
        return self.values.length()

def f() -> Int:
    var c = Counter(values: [])
    c.bump()
    c.bump()
    return c.size()
