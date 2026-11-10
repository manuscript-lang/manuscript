import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_ok, expect_error from "@std/test/test.ms",
	promise from "@std/concurrency/promise.ms",
)

type Failing:
	log: String
	id: Int
	closed: Bool = false
	fail: Bool = true

impl Closeable for Failing:
	var fn close() Unit!:
		if not self.closed:
			self.closed = true
			try append_file(self.log, "close {self.id}\n").wait()
			if self.fail:
				return error(
					Error(
						"close {self.id}", kind: "ECLOSE", details: {"id": "{self.id}"}
					)
				)

fn events(log: String) String:
	if bytes := read_file(log).wait(): return bytes.decode_utf8().get("")

	return ""

fn work(log: String, fail: Bool) Int!:
	_first := Failing(log.clone(), 1)
	_second := Failing(log.clone(), 2)
	if fail:
		return error(
			Error(
				"original body error", kind: "EBODY", details: {"id": "body"}
			)
		)

	return ok(77)

fn failure() Int!:
	return error(Error("original try error", kind: "ETRY", details: {"id": "try"}))

fn propagated(log: String) Int!:
	_first := Failing(log.clone(), 1)
	_second := Failing(log.clone(), 2)
	return ok(try failure())

fn borrowed(log: String, cause: Error) Int!:
	_first := Failing(log.clone(), 1)
	return error(cause)

fn handled(log: String) Int!:
	var first = Failing(log.clone(), 1)
	_ := first.close()
	return ok(77)

fn nested_success(log: String) Result[Int!, Error]:
	_first := Failing(log.clone(), 1)
	return ok(error(Error("inner error", kind: "EINNER")))

fn break_scope(log: String) Int!:
	for n in 0..2:
		_first := Failing(log.clone(), n)
		break

	return ok(77)

fn infallible(log: String) Int:
	_first := Failing(log.clone(), 1)
	return 77

test "a pending body error survives all scope close errors":
	dir := temporary("close-body-error-") | try expect_ok
	log := "{dir.path()}/events"
	cause := work(log, true) | try expect_error
	try expect_equal(cause.message, "original body error")
	try expect_equal(cause.kind, "EBODY")
	try expect_equal(cause.details["id"], "body")
	try expect_equal(events(log), "close 2\nclose 1\n")

test "a successful body returns the first close error":
	dir := temporary("close-body-success-") | try expect_ok
	log := "{dir.path()}/events"
	cause := work(log, false) | try expect_error
	try expect_equal(cause.message, "close 2")
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(cause.details["id"], "2")
	try expect_equal(events(log), "close 2\nclose 1\n")

test "a try error survives all scope close errors":
	dir := temporary("close-try-error-") | try expect_ok
	log := "{dir.path()}/events"
	cause := propagated(log) | try expect_error
	try expect_equal(cause.message, "original try error")
	try expect_equal(cause.kind, "ETRY")
	try expect_equal(cause.details["id"], "try")
	try expect_equal(events(log), "close 2\nclose 1\n")

test "a pending borrowed error retains the caller's fields":
	dir := temporary("close-borrowed-error-") | try expect_ok
	log := "{dir.path()}/events"
	original := Error("caller error", kind: "ECALLER", details: {"id": "caller"})
	cause := borrowed(log, original) | try expect_error
	try expect_equal(cause.message, "caller error")
	try expect_equal(cause.kind, "ECALLER")
	try expect_equal(cause.details["id"], "caller")
	try expect_equal(original.message, "caller error")
	try expect_equal(original.details["id"], "caller")
	try expect_equal(events(log), "close 1\n")

test "an explicitly handled close error is not returned again":
	dir := temporary("close-explicit-error-") | try expect_ok
	log := "{dir.path()}/events"
	try expect_equal(try handled(log), 77)
	try expect_equal(events(log), "close 1\n")

test "an error inside a successful payload does not suppress a close error":
	dir := temporary("close-nested-success-") | try expect_ok
	log := "{dir.path()}/events"
	cause := nested_success(log) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(events(log), "close 1\n")

test "a scope exited by break still returns its close error":
	dir := temporary("close-break-error-") | try expect_ok
	log := "{dir.path()}/events"
	cause := break_scope(log) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(events(log), "close 0\n")

test "a close error still faults when the function cannot return Error":
	dir := temporary("close-infallible-error-") | try expect_ok
	log := "{dir.path()}/events"
	work := promise(fn: ok(infallible(log)))
	cause := work.wait() | try expect_error
	try expect_equal(cause.kind, "EIO")
	try expect_equal(events(log), "close 1\n")

fn borrowed_ok(log: String, payload: String, fail: Bool) String!:
	_resource := Failing(log.clone(), 1, fail: fail)
	return ok(payload)

fn forward_ok(log: String, payload: String, fail: Bool) String!:
	return borrowed_ok(log, payload, fail)

fn mixed_error(source: Int!) String!:
	_number := try source
	return ok("fresh success")

fn forward_error(log: String, source: Int!) String!:
	_resource := Failing(log.clone(), 1)
	return mixed_error(source)

fn generic_error[E](log: String, cause: E) Int!E:
	_resource := Failing(log.clone(), 1)
	return error(cause)

type Domain:
	code: Int
	label: String

fn custom(log: String, fail: Bool) Int!Domain:
	_resource := Failing(log.clone(), 1)
	if fail: return error(Domain(73, "custom body"))

	return ok(77)

fn borrowed_custom(log: String, cause: Domain) Int!Domain:
	_resource := Failing(log.clone(), 1)
	return error(cause)

fn inner_close(log: String, cause: Error) Int!:
	if true:
		_resource := Failing(log.clone(), 1)
	return error(cause)

fn consume(value: Failing) Int:
	_values := [value]
	return 1

fn consumed_parameter(value: Failing, payload: String, take: Bool) String!:
	if take:
		_number := consume(value)
	return ok(payload)

test "a borrowed success survives a successful close through forwarding":
	dir := temporary("close-borrowed-ok-") | try expect_ok
	log := "{dir.path()}/events"
	original := "borrowed payload"
	try expect_equal(try forward_ok(log, original, false), original)
	try expect_equal(original, "borrowed payload")
	try expect_equal(events(log), "close 1\n")

test "a close error replaces borrowed success and leaves its source valid":
	dir := temporary("close-borrowed-success-failed-") | try expect_ok
	log := "{dir.path()}/events"
	original := "borrowed payload"
	cause := forward_ok(log, original, true) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(cause.details["id"], "1")
	try expect_equal(original, "borrowed payload")
	try expect_equal(events(log), "close 1\n")

test "a forwarded borrowed error is preserved across a failing close":
	dir := temporary("close-forwarded-error-") | try expect_ok
	log := "{dir.path()}/events"
	original: Int! = error(
		Error("forwarded body", kind: "EFORWARD", details: {"id": "source"})
	)
	cause := forward_error(log, original) | try expect_error
	try expect_equal(cause.message, "forwarded body")
	try expect_equal(cause.kind, "EFORWARD")
	try expect_equal(cause.details["id"], "source")

	source := original | try expect_error
	try expect_equal(source.message, "forwarded body")
	try expect_equal(events(log), "close 1\n")

test "generic errors retain their fields across a failing close":
	dir := temporary("close-generic-error-") | try expect_ok
	log := "{dir.path()}/events"
	cause := generic_error(log, Error("generic body", kind: "EGENERIC")) | try expect_error
	try expect_equal(cause.message, "generic body")
	try expect_equal(cause.kind, "EGENERIC")
	try expect_equal(events(log), "close 1\n")

test "a pending custom error survives an incompatible close error":
	dir := temporary("close-custom-error-") | try expect_ok
	log := "{dir.path()}/events"
	cause := custom(log, true) | try expect_error
	try expect_equal(cause.code, 73)
	try expect_equal(cause.label, "custom body")
	try expect_equal(events(log), "close 1\n")

test "a pending borrowed custom error retains the caller value":
	dir := temporary("close-custom-borrowed-") | try expect_ok
	log := "{dir.path()}/events"
	original := Domain(74, "borrowed custom")
	cause := borrowed_custom(log, original) | try expect_error
	try expect_equal(cause.code, 74)
	try expect_equal(cause.label, "borrowed custom")
	try expect_equal(original.label, "borrowed custom")
	try expect_equal(events(log), "close 1\n")

test "an incompatible close error still faults after pending success":
	dir := temporary("close-custom-success-") | try expect_ok
	log := "{dir.path()}/events"
	work := promise(fn: ok(custom(log, false)))
	cause := work.wait() | try expect_error
	try expect_equal(cause.kind, "EIO")
	try expect_equal(events(log), "close 1\n")

test "an earlier inner close error wins before the body selects its error":
	dir := temporary("close-inner-first-") | try expect_ok
	log := "{dir.path()}/events"
	original := Error("later body", kind: "ELATER")
	cause := inner_close(log, original) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(original.kind, "ELATER")
	try expect_equal(events(log), "close 1\n")

test "a consumed parameter closes on its retained path before borrowed success":
	dir := temporary("close-consumed-parameter-") | try expect_ok
	log := "{dir.path()}/events"
	payload := "still borrowed"
	cause := consumed_parameter(Failing(log.clone(), 1), payload, false) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(payload, "still borrowed")
	try expect_equal(events(log), "close 1\n")

fn whole_result(log: String, source: Int!, fail: Bool) Int!:
	_resource := Failing(log.clone(), 1, fail: fail)
	return source

type Holder:
	resource: Failing

fn holder_result[T](log: String, source: T!) T!:
	_holder := Holder(Failing(log.clone(), 1, fail: false))
	return source

fn overlapping(log: String, value: String, cause: Error, fail: Bool) String!:
	_resource := Failing(log.clone(), 1, fail: false)
	if fail: return error(cause)

	return ok(value)

test "whole Result forwarding preserves the body error and caller source":
	dir := temporary("close-whole-error-") | try expect_ok
	log := "{dir.path()}/events"
	original: Int! = error(
		Error("whole body", kind: "EWHOLE", details: {"id": "whole"})
	)
	cause := whole_result(log, original, true) | try expect_error
	try expect_equal(cause.message, "whole body")
	try expect_equal(cause.kind, "EWHOLE")
	try expect_equal(cause.details["id"], "whole")

	source := original | try expect_error
	try expect_equal(source.kind, "EWHOLE")
	try expect_equal(events(log), "close 1\n")

test "whole Result forwarding returns the first close error after success":
	dir := temporary("close-whole-success-") | try expect_ok
	log := "{dir.path()}/events"
	original: Int! = ok(73)
	cause := whole_result(log, original, true) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(try original, 73)
	try expect_equal(events(log), "close 1\n")

test "holder cleanup does not withdraw a generic whole Result borrow":
	dir := temporary("close-holder-result-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("holder body", kind: "EHOLDER"))
	cause := holder_result(log, original) | try expect_error
	try expect_equal(cause.message, "holder body")
	try expect_equal(cause.kind, "EHOLDER")

	source := original | try expect_error
	try expect_equal(source.kind, "EHOLDER")
	try expect_equal(events(log), "close 1\n")

test "overlapping borrowed errors normalize without copying borrowed success":
	dir := temporary("close-overlapping-") | try expect_ok
	first := "{dir.path()}/first"
	second := "{dir.path()}/second"
	value := "borrowed success"
	original := Error("borrowed overlap", kind: "EOVERLAP")
	try expect_equal(try overlapping(first, value, original, false), value)

	cause := overlapping(second, value, original, true) | try expect_error
	try expect_equal(cause.kind, "EOVERLAP")
	try expect_equal(original.message, "borrowed overlap")
	try expect_equal(events(first), "close 1\n")
	try expect_equal(events(second), "close 1\n")

type OwnHolder:
	resource: Failing

impl Closeable for OwnHolder:
	var fn close() Unit!:
		return ok(unit)

fn own_holder_result[T](log: String, source: T!) T!:
	_holder := OwnHolder(Failing(log.clone(), 1, fail: false))
	return source

fn generic_whole[T](log: String, source: T!) T!:
	_resource := Failing(log.clone(), 1, fail: false)
	return source

test "a holder with its own close still preserves a generic Result borrow":
	dir := temporary("close-own-holder-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("own holder body", kind: "EOWNHOLDER"))
	cause := own_holder_result(log, original) | try expect_error
	try expect_equal(cause.kind, "EOWNHOLDER")

	source := original | try expect_error
	try expect_equal(source.message, "own holder body")
	try expect_equal(events(log), "close 1\n")

test "a generic propagating closer consumes its whole Result without a forbidden copy":
	dir := temporary("close-generic-whole-") | try expect_ok
	log := "{dir.path()}/events"
	try expect_equal(
		try generic_whole[String](log, ok("moved payload")), "moved payload"
	)
	try expect_equal(events(log), "close 1\n")

fn resource_domain_error(log: String) Bool:
	result := generic_error(log, Failing(log.clone(), 2, fail: false))
	return result.is_error()

test "a generic resource error stays owned and closes exactly once":
	dir := temporary("close-resource-error-") | try expect_ok
	log := "{dir.path()}/events"
	try expect_equal(resource_domain_error(log), true)
	try expect_equal(events(log), "close 1\nclose 2\n")

fn moved_holder_result[T](log: String, source: T!) T!:
	resource := Failing(log.clone(), 1, fail: false)
	_holder := Holder(resource)
	return source

fn handled_result[T](log: String, source: T!) T!:
	var resource = Failing(log.clone(), 1)
	_ := resource.close()
	return source

fn nested_closure_result[T](log: String, source: T!) T!:
	_unused := fn:
		_resource := Failing(log.clone(), 1)
		return unit

	return source

test "a moved resource no longer contributes an outer close error":
	dir := temporary("close-result-scope-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("source", kind: "ESOURCE"))
	returned := moved_holder_result(log, original) | try expect_error
	try expect_equal(returned.kind, "ESOURCE")

	source := original | try expect_error
	try expect_equal(source.kind, "ESOURCE")
	try expect_equal(events(log), "close 1\n")

test "a handled close does not withdraw a whole Result borrow":
	dir := temporary("close-result-scope-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("source", kind: "ESOURCE"))
	returned := handled_result(log, original) | try expect_error
	try expect_equal(returned.kind, "ESOURCE")

	source := original | try expect_error
	try expect_equal(source.kind, "ESOURCE")
	try expect_equal(events(log), "close 1\n")

test "an uncalled closure cannot contribute an outer close error":
	dir := temporary("close-result-scope-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("source", kind: "ESOURCE"))
	returned := nested_closure_result(log, original) | try expect_error
	try expect_equal(returned.kind, "ESOURCE")

	source := original | try expect_error
	try expect_equal(source.kind, "ESOURCE")
	try expect_equal(events(log), "")

fn replaced_handled_result[T](log: String, source: T!) T!:
	var resource = Failing(log.clone(), 1, fail: false)
	resource = Failing(log.clone(), 2)

	_ := resource.close()
	return source

fn replaced_unhandled_result(log: String, source: Int!) Int!:
	var resource = Failing(log.clone(), 1, fail: false)
	_ := resource.close()
	resource = Failing(log.clone(), 2)
	return source

fn failing_replacement() Failing!:
	return error(Error("replacement", kind: "EREPLACE"))

fn replacement_exit(log: String) Int!:
	var resource = Failing(log.clone(), 1)
	resource = try failing_replacement()

	_ := resource.close()
	return ok(7)

fn captured_result[T](log: String, source: T!) T!:
	resource := Failing(log.clone(), 1, fail: false)
	_callbacks: List[fn() Int] = [fn: resource.id]
	return source

test "handled replacement lifetimes preserve whole Result borrowing":
	dir := temporary("close-result-lifetime-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("source", kind: "ESOURCE"))
	returned := replaced_handled_result(log, original) | try expect_error
	try expect_equal(returned.kind, "ESOURCE")

	source := original | try expect_error
	try expect_equal(source.kind, "ESOURCE")
	try expect_equal(events(log), "close 1\nclose 2\n")

test "a captured resource contributes no outer close error":
	dir := temporary("close-result-lifetime-") | try expect_ok
	log := "{dir.path()}/events"
	original: String! = error(Error("source", kind: "ESOURCE"))
	returned := captured_result(log, original) | try expect_error
	try expect_equal(returned.kind, "ESOURCE")

	source := original | try expect_error
	try expect_equal(source.kind, "ESOURCE")
	try expect_equal(events(log), "close 1\n")

test "an unhandled final replacement still propagates its close error":
	dir := temporary("close-result-unhandled-") | try expect_ok
	log := "{dir.path()}/events"
	original: Int! = ok(7)
	cause := replaced_unhandled_result(log, original) | try expect_error
	try expect_equal(cause.kind, "ECLOSE")
	try expect_equal(try original, 7)
	try expect_equal(events(log), "close 1\nclose 2\n")

test "a try exit before replacement still closes the old resource":
	dir := temporary("close-result-replacement-exit-") | try expect_ok
	log := "{dir.path()}/events"
	cause := replacement_exit(log) | try expect_error
	try expect_equal(cause.kind, "EREPLACE")
	try expect_equal(cause.message, "replacement")
	try expect_equal(events(log), "close 1\n")
