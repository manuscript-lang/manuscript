fn wrap(text: String) String?:
	return text + "x"

fn first_item(items: List[String]) Int:
	item := items.get(0)
	return item.length()

fn read_item(items: List[String]) Int:
	return items.get(0).length()

fn wrap_call(a: String, b: String) String?:
	return a + b

type Bag:
	items: List[String]

fn var Bag.add(text: String) Int:
	self.items.append(text)
	return self.items.length()
