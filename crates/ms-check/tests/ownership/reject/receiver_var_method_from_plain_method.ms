type Counter:
    values: List[Int]

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    fn twice() Unit:
        self.bump()  # error: does not change its receiver
