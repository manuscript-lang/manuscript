type Counter:
    values: List[Int]

fn var Counter.bump() Unit:
    self.values.append(1)

fn var Counter.twice() Unit:
    self.bump()
    self.bump()
