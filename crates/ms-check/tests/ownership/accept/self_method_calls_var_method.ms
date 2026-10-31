type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    var fn twice() Unit:
        self.bump()
        self.bump()
