type Counter:
	value: Int

fn Counter.next() Counter: Counter(self.value + 1)

fn make(create: fn() Int) Counter: Counter(create())

fn exercise() Int:
	return make(fn: 0).value
