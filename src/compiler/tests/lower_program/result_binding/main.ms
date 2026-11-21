import from_scalars from "@std/string.ms"

fn text_of(scalars: List[Int]) String:
	if text := from_scalars(scalars): return text
	return ""

fn main() Void:
	print(text_of([104, 105]))
