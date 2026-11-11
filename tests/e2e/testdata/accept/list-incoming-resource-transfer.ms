import (
	Closeable, panic from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Door:
	id: Int
	log: String
	closed: Bool = false
	fail: Bool = false

impl Closeable for Door:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			append_file(self.log, "{self.id},").wait()?
			if self.fail: return error(Error("close failed"))

fn events(log: String) String!:
	return ok((read_file(log).wait()?).decode_utf8().get(""))

fn named(log: String, op: Int, index: Int, fail: Bool = false) Unit:
	var items = [Door(1, log.clone(), fail: fail)]

	if op == 0: items.set(index, Door(2, log))
	else if op == 1: items.insert(index, Door(2, log))
	else if op == 2:
		_old := items.replace(index, Door(2, log))
	else if op == 3: items.append(Door(2, log))
	else: items.prepend(Door(2, log))

fn computed(log: String, op: Int, index: Int, fail: Bool = false) Unit:
	if op == 0: [Door(1, log.clone(), fail: fail)].set(index, Door(2, log))
	else if op == 1: [Door(1, log.clone(), fail: fail)].insert(index, Door(2, log))
	else if op == 2:
		_old := [Door(1, log.clone(), fail: fail)].replace(index, Door(2, log))
	else if op == 3: [Door(1, log.clone(), fail: fail)].append(Door(2, log))
	else: [Door(1, log.clone(), fail: fail)].prepend(Door(2, log))

test "named and computed bad bounds close incoming before existing":
	for op in 0..3:
		for index in [-2, 2]:
			tmp := temporary("list-transfer-")?
			log := "{tmp.path()}/log"
			expect_contains((expect_fault(fn: named(log.clone(), op, index))?), "index")?
			expect_equal((events(log)?), "2,1,")?

			temp := temporary("list-computed-transfer-")?
			other := "{temp.path()}/log"
			expect_contains(
				(expect_fault(fn: computed(other.clone(), op, index))?),
				"index",
			)?
			expect_equal((events(other)?), "2,1,")?

test "successful direct and computed transfers close each owner once":
	for op in 0..5:
		tmp := temporary("list-transfer-ok-")?
		log := "{tmp.path()}/log"
		named(log.clone(), op, 0)

		expected := if op == 3: "2,1," else: "1,2,"
		expect_equal((events(log)?), expected)?

		temp := temporary("list-computed-ok-")?
		other := "{temp.path()}/log"
		computed(other.clone(), op, 0)

		computed_expected := if op == 2 or op == 3: "2,1," else: "1,2,"
		expect_equal((events(other)?), computed_expected)?

fn later_fault(log: String) Unit:
	var items = [Door(1, log.clone())]
	items.set(value: Door(2, log), index: panic("later operand"))

fn bad_index() Int!:
	return error(Error("index failed"))

fn later_try(log: String) Unit!:
	var items = [Door(1, log.clone())]
	items.set(value: Door(2, log), index: bad_index()?)

test "later named operand faults and try exits preserve incoming owner":
	tmp := temporary("list-later-fault-")?
	log := "{tmp.path()}/log"
	expect_contains((expect_fault(fn: later_fault(log.clone()))?), "later operand")?
	expect_equal((events(log)?), "2,1,")?

	temp := temporary("list-later-try-")?
	other := "{temp.path()}/log"
	expect_equal(later_try(other.clone()).is_error(), true)?
	expect_equal((events(other)?), "2,1,")?

test "failed old close preserves pending incoming owner":
	tmp := temporary("list-old-close-")?
	log := "{tmp.path()}/log"
	message := expect_fault(fn: named(log.clone(), 0, 0, true))?
	expect_contains(message, "closed")?
	expect_equal((events(log)?), "1,2,")?

	temp := temporary("list-computed-old-close-")?
	other := "{temp.path()}/log"
	error := expect_fault(fn: computed(other.clone(), 0, 0, true))?
	expect_contains(error, "closed")?
	expect_equal((events(other)?), "1,2,")?

type Holder:
	items: List[Door]

fn field(log: String) Unit:
	var holder = Holder([Door(1, log.clone())])
	holder.items.set(3, Door(2, log))

fn slot(log: String) Unit:
	var items = [Door(1, log.clone())]
	action := fn(index: Int): items.set(index, Door(2, log.clone()))
	action(3)

test "field and closure-slot receivers retain cleanup on fault":
	tmp := temporary("list-field-")?
	log := "{tmp.path()}/log"
	expect_contains((expect_fault(fn: field(log.clone()))?), "index")?
	expect_equal((events(log)?), "2,1,")?

	temp := temporary("list-slot-")?
	other := "{temp.path()}/log"
	expect_contains((expect_fault(fn: slot(other))?), "index")?
	expect_equal((events(other)?), "2,1,")?

fn optional(log: String, index: Int) Unit:
	var items: List[Door?] = [Door(1, log.clone())]
	items.set(index, Door(2, log))

fn computed_failed_new_close(log: String) Unit:
	_old := [Door(1, log.clone())].replace(0, Door(2, log, fail: true))

test "implicit optional payload and outgoing replacement survive cleanup faults":
	tmp := temporary("list-optional-")?
	log := "{tmp.path()}/log"
	expect_contains((expect_fault(fn: optional(log.clone(), 3))?), "index")?
	expect_equal((events(log)?), "2,1,")?

	temp := temporary("list-replace-new-close-")?
	other := "{temp.path()}/log"
	message := expect_fault(fn: computed_failed_new_close(other.clone()))?
	expect_contains(message, "closed")?
	expect_equal((events(other)?), "2,1,")?

fn repeated(log: String) Unit:
	var items: List[Door] = []
	for id in 0..40:
		items.append(Door(id, log.clone()))
	for id in 0..40:
		_old := items.replace(id, Door(id + 40, log.clone()))

test "repeated successful transfers retire only their own cleanup":
	tmp := temporary("list-repeated-")?
	log := "{tmp.path()}/log"
	repeated(log)

	var expected = ""
	for id in 0..40: expected = "{expected}{id},"
	for id in 0..40: expected = "{expected}{79 - id},"
	expect_equal((events(log)?), expected)?

type PanicDoor:
	id: Int
	log: String
	fail: Bool
	closed: Bool = false

impl Closeable for PanicDoor:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			append_file(self.log, "{self.id},").wait()?
			if self.fail: panic("capture close panic")

fn captured(log: String, id: Int, fail: Bool) fn() Int:
	door := PanicDoor(id, log, fail)
	return fn: door.id

type Envelope:
	id: Int
	log: String
	callback: fn() Int
	closed: Bool = false

impl Closeable for Envelope:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			append_file(self.log, "{self.id},").wait()?

fn callback_drop(log: String) Unit:
	var items = [Envelope(1, log.clone(), captured(log.clone(), 3, true))]
	items.set(0, Envelope(2, log, fn: 4))

test "faulting captured close during detached old drop preserves new list owner":
	tmp := temporary("list-callback-drop-")?
	log := "{tmp.path()}/log"
	message := expect_fault(fn: callback_drop(log.clone()))?
	expect_contains(message, "capture close panic")?
	expect_equal((events(log)?), "1,3,2,")?

type EnvelopeHolder:
	items: List[Envelope]

fn callback_places(log: String, kind: Int) Unit:
	if kind == 0:
		var holder = EnvelopeHolder(
			[Envelope(1, log.clone(), captured(log.clone(), 3, true))]
		)
		holder.items.set(0, Envelope(2, log, fn: 4))
	else if kind == 1:
		var groups = [[Envelope(1, log.clone(), captured(log.clone(), 3, true))]]
		groups[0].set(0, Envelope(2, log, fn: 4))
	else if kind == 2:
		var items = [Envelope(1, log.clone(), captured(log.clone(), 3, true))]
		action := fn: items.set(0, Envelope(2, log.clone(), fn: 4))
		action()
	else:
		[Envelope(1, log.clone(), captured(log.clone(), 3, true))].set(
			0,
			Envelope(2, log, fn: 4),
		)

test "old capture drop fault observes updated field indexed slot and computed receivers":
	for kind in 0..4:
		tmp := temporary("list-place-callback-")?
		log := "{tmp.path()}/log"
		message := expect_fault(fn: callback_places(log.clone(), kind))?
		expect_contains(message, "capture close panic")?
		expect_equal((events(log)?), "1,3,2,")?

fn owned_named(log: String, index: Int) Unit:
	var items = [Door(1, log.clone())]
	next := Door(2, log)
	items.insert(index, next)

fn valid_later() Int!: return ok(0)

fn succeeding_try(log: String) Unit!:
	var items = [Door(1, log.clone())]
	items.set(value: Door(2, log), index: valid_later()?)

test "valid negative end and named owner transfers preserve single close":
	for op in [0, 1, 2]:
		tmp := temporary("list-negative-ok-")?
		log := "{tmp.path()}/log"
		named(log.clone(), op, -1)
		expect_equal((events(log)?), "1,2,")?

	tmp := temporary("list-end-ok-")?
	log := "{tmp.path()}/log"
	owned_named(log.clone(), 1)
	expect_equal((events(log)?), "2,1,")?

	temp := temporary("list-named-fault-")?
	other := "{temp.path()}/log"
	expect_contains((expect_fault(fn: owned_named(other.clone(), 2))?), "index")?
	expect_equal((events(other)?), "2,1,")?

	success := temporary("list-success-try-")?
	path := "{success.path()}/log"
	succeeding_try(path.clone())?
	expect_equal((events(path)?), "1,2,")?

fn after_pop(var items: List[Door]) Int:
	_removed := items.pop()
	return 0

fn changed_length(log: String) Unit:
	var items = [Door(1, log.clone())]
	items.set(value: Door(2, log), index: after_pop(var items))

test "final bounds use receiver after later operand mutation":
	tmp := temporary("list-current-bounds-")?
	log := "{tmp.path()}/log"
	expect_contains((expect_fault(fn: changed_length(log.clone()))?), "index")?
	expect_equal((events(log)?), "1,2,")?

fn optional_list(log: String) List[Door?]:
	return [Door(1, log)]

fn computed_absent(log: String) Unit:
	optional_list(log).set(0, none)

fn computed_arg_fault(log: String) Unit:
	optional_list(log).append(panic("incoming failed"))

test "computed receiver closes when payload absent or construction faults":
	tmp := temporary("list-absent-")?
	log := "{tmp.path()}/log"
	computed_absent(log.clone())
	expect_equal((events(log)?), "1,")?

	temp := temporary("list-arg-fault-")?
	other := "{temp.path()}/log"
	expect_contains(
		(expect_fault(fn: computed_arg_fault(other.clone()))?),
		"incoming failed",
	)?
	expect_equal((events(other)?), "1,")?
