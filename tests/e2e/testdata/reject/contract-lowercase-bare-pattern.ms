type item:
	n: Int

interface Get:
	fn get() Int

fn item.get() Int: self.n

fn read(value: Get) Int:
	match value:
		item: return 0
		_: return 0
