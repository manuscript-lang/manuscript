type Counter:
    values: List[Int]

impl Counter:
    var def bump() -> Unit:
        self.values.append(1)

    def twice() -> Unit:
        self.bump()  # error: does not change its receiver
