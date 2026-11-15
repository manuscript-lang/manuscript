fn discarded(flag: Bool) Void:
	match flag:
		true:
			_marker := 1
		false: 2

fn unit_value(flag: Bool) Void:
	value: Void := match flag:
		true:
			_marker := 1
		false: void

	return value

fn exiting(flag: Bool) Int:
	value: Int := match flag:
		true: return 1
		false: 2

	return value
