export type Counter:
    count: Int

fn Counter.total(other: Int) Int:
    return self.count + other

fn var Counter.bump(by: Int) Int:
    self.count += by
    return self.count

export fn make(start: Int) Counter:
    return Counter(count: start)
