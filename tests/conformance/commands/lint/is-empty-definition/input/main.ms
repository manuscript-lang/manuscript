type Bag {
	items List[Int]
}

fn Bag.is_empty() Bool {
	return self.items.length() == 0
}

fn main() Void {
	bag := Bag(items: [])
	print(bag.is_empty())
}
