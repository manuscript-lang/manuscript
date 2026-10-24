type Counter:
    values: List[Int]

impl Counter:
    var def bump() -> Unit:
        self.values.append(1)

    var def twice() -> Unit:
        self.bump()
        self.bump()
