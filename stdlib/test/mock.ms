import caller_site, fail, repr from "@std/test/test.ms"

/*
Mocks: stand-ins that answer with preset values, record every call, and let a test assert
on the calls. `MockN` takes N arguments (N = 0..3) and returns `R`. Build one with
`MockN[...](fallback: value)`, hand it to code as `fn a, b: mock.call(a, b)`, then check
`calls` or use the `expect_*` methods. `returns_once(value)` queues answers used before the
fallback, in order. A mock owns its calls; arguments are cloned in, so the caller keeps its
values. Replace a dependency in a test by passing a mock through an interface or a function
parameter; to replace an effect without a parameter see `fake` in `@std/test/test.ms`.
*/

// A mock of a function taking 0 arguments and returning R: records calls, answers from
// a queue, then from the fallback.
export type Mock0[R: Clonable]:
	// The answer once the queue is used up.
	fallback: R
	// One entry per call, oldest first; a call without arguments records its index.
	calls: List[Int] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0

// Records the call and answers with the next queued value, else the fallback.
fn var Mock0[R].call() R:
	self.calls.append(self.calls.length())

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock0[R].returns_once(value: R) Void:
	self.queue.append(value)

// Forgets recorded calls and queued answers; the fallback stays.
fn var Mock0[R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0

// Fails unless called exactly `times` times.
fn Mock0[R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock0[R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// A mock of a function taking 1 argument and returning R: records calls, answers from a
// queue, then from the fallback.
export type Mock1[A: Clonable & Equal, R: Clonable]:
	// The answer once the queue is used up.
	fallback: R
	// One entry per call, oldest first.
	calls: List[A] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0

// Records the call and answers with the next queued value, else the fallback.
fn var Mock1[A, R].call(a: A) R:
	self.calls.append(a.clone())

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock1[A, R].returns_once(value: R) Void:
	self.queue.append(value)

// Forgets recorded calls and queued answers; the fallback stays.
fn var Mock1[A, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0

// Fails unless called exactly `times` times.
fn Mock1[A, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock1[A, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails unless some call had these arguments.
fn Mock1[A, R].expect_called_with(a: A, site: String = caller_site()) Void!:
	want := a
	for call in self.calls:
		if call == want: return ok()
	return fail(f"expected a call with {repr(want)}, got {repr(self.calls)}", site)

// Fails unless the most recent call had these arguments.
fn Mock1[A, R].expect_last_called_with(a: A, site: String = caller_site()) Void!:
	want := a
	if self.calls.length() == 0: return fail("expected a call, got none", site)

	last := self.calls[self.calls.length() - 1]
	if last == want: return ok()

	return fail(f"expected last call with {repr(want)}, got {repr(last)}", site)

// The arguments of one call to a `Mock2`.
export type Call2[A: Clonable & Equal, B: Clonable & Equal]:
	// Argument 1 of the call.
	a: A
	// Argument 2 of the call.
	b: B

// A mock of a function taking 2 arguments and returning R: records calls, answers from
// a queue, then from the fallback.
export type Mock2[A: Clonable & Equal, B: Clonable & Equal, R: Clonable]:
	// The answer once the queue is used up.
	fallback: R
	// One entry per call, oldest first.
	calls: List[Call2[A, B]] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0

// Records the call and answers with the next queued value, else the fallback.
fn var Mock2[A, B, R].call(a: A, b: B) R:
	self.calls.append(Call2[A, B](a.clone(), b.clone()))

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock2[A, B, R].returns_once(value: R) Void:
	self.queue.append(value)

// Forgets recorded calls and queued answers; the fallback stays.
fn var Mock2[A, B, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0

// Fails unless called exactly `times` times.
fn Mock2[A, B, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock2[A, B, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails unless some call had these arguments.
fn Mock2[A, B, R].expect_called_with(a: A, b: B, site: String = caller_site()) Void!:
	want := Call2[A, B](a, b)
	for call in self.calls:
		if call == want: return ok()
	return fail(f"expected a call with {repr(want)}, got {repr(self.calls)}", site)

// Fails unless the most recent call had these arguments.
fn Mock2[A, B, R].expect_last_called_with(
	a: A,
	b: B,
	site: String = caller_site(),
) Void!:
	want := Call2[A, B](a, b)
	if self.calls.length() == 0: return fail("expected a call, got none", site)

	last := self.calls[self.calls.length() - 1]
	if last == want: return ok()

	return fail(f"expected last call with {repr(want)}, got {repr(last)}", site)

// The arguments of one call to a `Mock3`.
export type Call3[A: Clonable & Equal, B: Clonable & Equal, C: Clonable & Equal]:
	// Argument 1 of the call.
	a: A
	// Argument 2 of the call.
	b: B
	// Argument 3 of the call.
	c: C

// A mock of a function taking 3 arguments and returning R: records calls, answers from
// a queue, then from the fallback.
export type Mock3[
	A: Clonable & Equal,
	B: Clonable & Equal,
	C: Clonable & Equal,
	R: Clonable,
]:
	// The answer once the queue is used up.
	fallback: R
	// One entry per call, oldest first.
	calls: List[Call3[A, B, C]] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0

// Records the call and answers with the next queued value, else the fallback.
fn var Mock3[A, B, C, R].call(a: A, b: B, c: C) R:
	self.calls.append(Call3[A, B, C](a.clone(), b.clone(), c.clone()))

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock3[A, B, C, R].returns_once(value: R) Void:
	self.queue.append(value)

// Forgets recorded calls and queued answers; the fallback stays.
fn var Mock3[A, B, C, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0

// Fails unless called exactly `times` times.
fn Mock3[A, B, C, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock3[A, B, C, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails unless some call had these arguments.
fn Mock3[A, B, C, R].expect_called_with(
	a: A,
	b: B,
	c: C,
	site: String = caller_site(),
) Void!:
	want := Call3[A, B, C](a, b, c)
	for call in self.calls:
		if call == want: return ok()
	return fail(f"expected a call with {repr(want)}, got {repr(self.calls)}", site)

// Fails unless the most recent call had these arguments.
fn Mock3[A, B, C, R].expect_last_called_with(
	a: A,
	b: B,
	c: C,
	site: String = caller_site(),
) Void!:
	want := Call3[A, B, C](a, b, c)
	if self.calls.length() == 0: return fail("expected a call, got none", site)

	last := self.calls[self.calls.length() - 1]
	if last == want: return ok()

	return fail(f"expected last call with {repr(want)}, got {repr(last)}", site)
