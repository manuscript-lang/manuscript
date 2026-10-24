type Counter:
    values: List[Int]

impl Counter:
    def bump() -> Unit:
        self.values.append(1)  # error: does not change its receiver
