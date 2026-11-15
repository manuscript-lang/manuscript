type Counter:
    values: List[Int]

fn var Counter.bump() Void:
    self.values.append(1)

fn var Counter.twice() Void:
    self.bump()
    self.bump()
