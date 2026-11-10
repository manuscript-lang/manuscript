type Counter:
	value: Int

impl Counter:
	fn next() Counter: Counter(self.value + 1)

fn make(create: fn() Int) Counter: Counter(create())

fn exercise(seed: Int) Int:
	return make(
		fn:
			nested := seed + 1
			return Counter(nested).next().value
	).next().value
