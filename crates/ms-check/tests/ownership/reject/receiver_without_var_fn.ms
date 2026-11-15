type Counter:
    values: List[Int]

fn Counter.bump() Void:
    self.values.append(1)  // error: does not change its receiver
