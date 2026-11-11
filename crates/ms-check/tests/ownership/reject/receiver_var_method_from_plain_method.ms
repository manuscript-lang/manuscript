type Counter:
    values: List[Int]

fn var Counter.bump() Unit:
    self.values.append(1)

fn Counter.twice() Unit:
    self.bump()  // error: does not change its receiver
