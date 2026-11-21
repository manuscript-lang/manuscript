type Counter:
	value: Int

fn make_fixture() Counter:
	return Counter(0)

fn var Counter.before_each() Void!:
	self.value = 1

fn var Counter.after_each() Void!:
	self.value = 10

test "reads the fixture":
	if fixture.value != 1: return error(Error("not reset"))

bench "benchmark has no fixture" per 10:
	return
