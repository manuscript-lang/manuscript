fn classify(flag: Bool) Int:
	value: Int := match flag:
		true:
			_marker := 1
		false: 2

	return value
