type Counter:
	value: Int

fn Counter.next(amount: Int = 1) Counter: Counter(self.value + amount)

fn make(value: Int) Counter: Counter(value)

fn bad_receiver() Counter: make("wrong").next()

fn bad_label() Counter: Counter(0).next(mystery: 1)

fn bad_arity() Counter: Counter(0).next(1, 2)

fn bad_specialization() Counter: Counter(0).next[Int]()
