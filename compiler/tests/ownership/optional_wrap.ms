type Parsed:
	kind: Int
	event: String?

fn from_param(name: String) Parsed:
	return Parsed(1, name)

fn from_local() Parsed:
	text := "a" + "b"
	return Parsed(1, text)

fn twice(name: String) Int:
	first := Parsed(1, name)
	second := Parsed(2, name)
	return first.kind + second.kind

fn wrapped(name: String) String?:
	return name

fn kept(name: String) String?:
	label := name
	return label
