export fn scaled(value: Int, by: Int = 3, offset: Int = 1) Int:
	return value * by + offset

export fn tagged(name: String, tag: String = "!") String:
	return name + tag

export fn ignore[T](value: T, loud: Bool = false) Void:
	if loud: return
