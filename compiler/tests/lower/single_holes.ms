type Tag:
	name: String
	note: String?

fn shown(s: String) Void:
	print(f"{s}")

fn digits(i: Int) String:
	return f"{i}"

fn kept(s: String) String:
	return f"{s}"

fn grown(n: Int) String:
	var text = ""
	for i in 0..n:
		text += f"{i}"
	return text

fn tagged(name: String) Tag:
	return Tag(name, note: "plain")

fn literal() String?:
	return "x"

fn failure(reason: String) Error:
	return Error(f"bad: {reason}", kind: "EINVAL")

fn identity[T](value: T) T:
	return value

fn typed(n: Int) Int:
	return identity[Int](n)

fn empty_list() Int:
	items := List[Int]()
	return items.length()

fn empty_map() Int:
	counts := Map[String, Int]()
	return counts.length()

fn main() Int:
	shown("a")

	a := digits(3)
	b := kept(a)
	c := grown(3)
	d := tagged(b)
	shown(d.name)
	shown(literal().get_or("none"))
	shown(failure(c).message)
	return typed(1) + empty_list() + empty_map()
