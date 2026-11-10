fn discarded(flag: Bool) Unit:
	match flag:
		true:
			_marker := 1
		false: 2

fn unit_value(flag: Bool) Unit:
	value: Unit = match flag:
		true:
			_marker := 1
		false: unit

	return value

fn exiting(flag: Bool) Int:
	value: Int = match flag:
		true: return 1
		false: 2

	return value
