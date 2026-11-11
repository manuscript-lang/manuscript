type Counter:
    values: List[Int]

fn var Counter.bump() Unit:
    self.values.append(1)

fn Counter.size() Int:
    return self.values.length()

fn f() Int:
    var c = Counter(values: [])
    c.bump()
    c.bump()
    return c.size()
