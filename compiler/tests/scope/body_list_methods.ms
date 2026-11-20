// Methods of the built-in List, found through the prelude's impls: the row's List[T]
// and the receiver's List[Int] are one type.
fn count(items: List[Int]) Int:
	return items.length()

fn grow(var items: List[Int]) Void:
	items.append(items.length())

fn wrong(items: List[Int]) Void:
	items.append(1)
