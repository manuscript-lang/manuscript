import expect_equal from "@std/test/test.ms"

type item:
	n: Int

interface Get:
	fn get() Int

fn item.get() Int: self.n

fn read(value: Get) Int:
	match value:
		item(receiver): return receiver.n
		_: return 0

test "lowercase contract patterns require an explicit receiver":
	expect_equal(read(item(n: 7)), 7)?
