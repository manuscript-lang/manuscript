type Counter:
    values: List[Int]

fn var Counter.bump() Void:
    self.values.append(1)

fn Counter.twice() Void:
    self.bump()  // error: does not change its receiver
