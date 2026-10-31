type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    fn size() Int:
        return self.values.length()

fn f() Int:
    var c = Counter(values: [])
    c.bump()
    c.bump()
    return c.size()
