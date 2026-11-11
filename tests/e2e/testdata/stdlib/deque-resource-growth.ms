import (
	Deque from "@std/collections/deque.ms",
	Closeable, panic from "@std/core.ms",
	FileHandle, OpenMode, append_file, open, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_error, expect_fault from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String

impl Closeable for Door:
	var fn close() Unit!:
		append_file(self.log, "{self.id},").wait()?

fn events(log: String) String!:
	return ok((read_file(log).wait()?).decode_utf8().get(""))

// A nonzero start is required to exercise the old copying growth path.
fn grow(log: String, front: Bool, wrapped: Bool) Unit!:
	var queue = Deque[Door]()
	for id in 0..4:
		queue.push_back(Door(id, log.clone()))

	if wrapped:
		queue.pop_front()
		queue.push_back(Door(4, log.clone()))

	before := events(log)?

	if front:
		queue.push_front(Door(5, log.clone()))
	else:
		queue.push_back(Door(5, log.clone()))

	expect_equal((events(log)?), before)?
	expect_equal(queue.length(), 5)?
	expect_equal(queue.front().get().id, if front: 5 else: (if wrapped: 1 else: 0))?
	expect_equal(queue.back().get().id, if front: (if wrapped: 4 else: 3) else: 5)?

	// Popped values remain owned by these bindings until the helper exits.
	first := queue.pop_front().get()
	last := queue.pop_back().get()
	expect_equal((events(log)?), before)?
	expect_equal(first.id, if front: 5 else: (if wrapped: 1 else: 0))?
	expect_equal(last.id, if front: (if wrapped: 4 else: 3) else: 5)?

fn expect_once(log: String, ids: List[Int]) Unit!:
	actual := (events(log)?).split(",").filter(fn value: value != "").sorted()
	expect_equal(actual, ids.map(fn id: "{id}").sorted())?

test "deque growth moves resource owners from either end":
	for front in [false, true]:
		for wrapped in [false, true]:
			tmp := temporary("deque-resource-")?
			log := "{tmp.path()}/log"
			append_file(log, "").wait()?
			grow(log.clone(), front, wrapped)?
			expect_once(log, if wrapped: [0, 1, 2, 3, 4, 5] else: [0, 1, 2, 3, 5])?

type Holder:
	door: Door
	label: String

fn nested(log: String) Unit!:
	var queue = Deque[Holder?]()
	queue.push_back(Holder(Door(0, log.clone()), "first"))
	queue.push_back(none)
	queue.push_back(Holder(Door(1, log.clone()), "second"))
	queue.push_back(none)
	queue.pop_front()
	queue.push_back(Holder(Door(2, log.clone()), "third"))
	queue.push_back(Holder(Door(3, log.clone()), "fourth"))
	expect_equal((events(log)?), "0,")?
	expect_equal(queue.length(), 5)?

	var popped: List[Int] = []

	while not queue.is_empty():
		item := queue.pop_front().get()

		if holder := item:
			popped.append(holder.door.id)
		else:
			popped.append(-1)

	expect_equal(popped, [-1, 1, -1, 2, 3])?

test "deque growth keeps absent optional slots and nested resource owners":
	tmp := temporary("deque-nested-")?
	log := "{tmp.path()}/log"
	append_file(log, "").wait()?
	nested(log.clone())?
	expect_once(log, [0, 1, 2, 3])?

fn interrupted(log: String, fault: Bool) Unit!:
	var queue = Deque[Door]()
	for id in 0..4:
		queue.push_front(Door(id, log.clone()))
	queue.pop_back()
	queue.push_front(Door(4, log.clone()))
	queue.push_back(Door(5, log.clone()))
	expect_equal((events(log)?), "0,")?
	if fault: panic("after deque growth")
	return error(Error("after deque growth"))

test "grown resource deques close each owner once on error and fault exits":
	tmp := temporary("deque-error-")?
	log := "{tmp.path()}/log"
	append_file(log, "").wait()?

	failure := expect_error(interrupted(log.clone(), false))?
	expect_equal(failure.message, "after deque growth")?
	expect_once(log, [0, 1, 2, 3, 4, 5])?

	other := "{tmp.path()}/fault"
	append_file(other, "").wait()?
	expect_contains(
		(expect_fault(fn: interrupted(other.clone(), true).get())?),
		"after deque growth",
	)?
	expect_once(other, [0, 1, 2, 3, 4, 5])?

test "wrapped growth leaves opaque native file handles usable":
	tmp := temporary("deque-review-native-")?
	path := "{tmp.path()}/data"
	append_file(path, "still open").wait()?

	for front in [false, true]:
		var q = Deque[FileHandle]()
		for unused in 0..4:
			q.push_back(open(path, OpenMode.ReadWrite)?)
		q.pop_front()
		q.push_back(open(path, OpenMode.ReadWrite)?)

		if front:
			q.push_front(open(path, OpenMode.ReadWrite)?)
		else:
			q.push_back(open(path, OpenMode.ReadWrite)?)

		while not q.is_empty():
			var handle = q.pop_front().get()
			content := handle.read_file()?
			expect_equal(content.decode_utf8().get(""), "still open")?
			handle.sync()?
			handle.close()?
