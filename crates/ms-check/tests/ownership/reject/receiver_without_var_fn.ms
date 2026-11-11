type Counter:
    values: List[Int]

fn Counter.bump() Unit:
    self.values.append(1)  // error: does not change its receiver
