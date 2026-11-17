import caller_site, fail, repr from "@std/test/test.ms"

/*
Mocks: stand-ins that answer with preset values, record every call, and let a test assert
on the calls. `MockN` takes N arguments (N = 0..3) and returns `R`. Build one with
`MockN[...](fallback: value)` and hand it to code as `fn a, b: mock.call(a, b)`. An answer
comes from the first matching `returns_for` rule, else the next `returns_once` value, else
the fallback. Then check `calls` or use the `expect_*` methods. `R` may be a Result or an
optional, so a mock can fail or return nothing on demand. A mock owns its calls; arguments
are cloned in, so the caller keeps its values. To replace a function the code reaches
directly, run the test body under `fake` in `@std/test/test.ms` with a closure over a mock.
*/

// A mock of a function taking 0 arguments and returning R: records calls and answers
// from rules, a queue, then the fallback.
export type Mock0[R: Clonable]:
	// The answer when no rule or queued answer applies.
	fallback: R
	// One entry per call, oldest first; a call without arguments records its index.
	calls: List[Int] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0

// Records the call and answers: the first matching rule, else the next queued value,
// else the fallback.
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

// Forgets recorded calls, queued answers and rules; the fallback stays.
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

// Fails while queued answers from `returns_once` remain unused.
fn Mock0[R].expect_answers_used(site: String = caller_site()) Void!:
	if self.used == self.queue.length(): return ok()
	return fail(
		f"{self.queue.length() - self.used} queued answers were never used",
		site,
	)

// A mock of a function taking 1 argument and returning R: records calls and answers
// from rules, a queue, then the fallback.
export type Mock1[A: Clonable & Equal, R: Clonable]:
	// The answer when no rule or queued answer applies.
	fallback: R
	// One entry per call, oldest first.
	calls: List[A] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0
	// The arguments of each `returns_for` rule, parallel to `rule_answers`.
	rule_args: List[A] = []
	// The answer of each `returns_for` rule; the first matching rule wins.
	rule_answers: List[R] = []

// Records the call and answers: the first matching rule, else the next queued value,
// else the fallback.
fn var Mock1[A, R].call(a: A) R:
	self.calls.append(a.clone())
	for i in 0..self.rule_args.length():
		if self.rule_args[i] == a: return self.rule_answers[i].clone()

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock1[A, R].returns_once(value: R) Void:
	self.queue.append(value)

// Answers `value` whenever called with these arguments, ahead of the queue and the
// fallback.
fn var Mock1[A, R].returns_for(a: A, value: R) Void:
	self.rule_args.append(a.clone())
	self.rule_answers.append(value)

// Forgets recorded calls, queued answers and rules; the fallback stays.
fn var Mock1[A, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0
	self.rule_args = []
	self.rule_answers = []

// Fails unless called exactly `times` times.
fn Mock1[A, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock1[A, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails while queued answers from `returns_once` remain unused.
fn Mock1[A, R].expect_answers_used(site: String = caller_site()) Void!:
	if self.used == self.queue.length(): return ok()
	return fail(
		f"{self.queue.length() - self.used} queued answers were never used",
		site,
	)

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

// Fails unless some call satisfies `check`, for arguments that are only partly known.
fn Mock1[A, R].expect_called_matching(
	check: fn(A) Bool,
	site: String = caller_site()
) Void!:
	for call in self.calls:
		if check(call): return ok()
	return fail(f"no call matched, got {repr(self.calls)}", site)

// The arguments of one call to a `Mock2`.
export type Call2[A: Clonable & Equal, B: Clonable & Equal]:
	// Argument 1 of the call.
	a: A
	// Argument 2 of the call.
	b: B

// A mock of a function taking 2 arguments and returning R: records calls and answers
// from rules, a queue, then the fallback.
export type Mock2[A: Clonable & Equal, B: Clonable & Equal, R: Clonable]:
	// The answer when no rule or queued answer applies.
	fallback: R
	// One entry per call, oldest first.
	calls: List[Call2[A, B]] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0
	// The arguments of each `returns_for` rule, parallel to `rule_answers`.
	rule_args: List[Call2[A, B]] = []
	// The answer of each `returns_for` rule; the first matching rule wins.
	rule_answers: List[R] = []

// Records the call and answers: the first matching rule, else the next queued value,
// else the fallback.
fn var Mock2[A, B, R].call(a: A, b: B) R:
	self.calls.append(Call2[A, B](a.clone(), b.clone()))
	for i in 0..self.rule_args.length():
		if self.rule_args[i] == Call2[A, B](a.clone(), b.clone()): return (
			self
			.rule_answers[i]
			.clone()
		)

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock2[A, B, R].returns_once(value: R) Void:
	self.queue.append(value)

// Answers `value` whenever called with these arguments, ahead of the queue and the
// fallback.
fn var Mock2[A, B, R].returns_for(a: A, b: B, value: R) Void:
	self.rule_args.append(Call2[A, B](a.clone(), b.clone()))
	self.rule_answers.append(value)

// Forgets recorded calls, queued answers and rules; the fallback stays.
fn var Mock2[A, B, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0
	self.rule_args = []
	self.rule_answers = []

// Fails unless called exactly `times` times.
fn Mock2[A, B, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock2[A, B, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails while queued answers from `returns_once` remain unused.
fn Mock2[A, B, R].expect_answers_used(site: String = caller_site()) Void!:
	if self.used == self.queue.length(): return ok()
	return fail(
		f"{self.queue.length() - self.used} queued answers were never used",
		site,
	)

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

// Fails unless some call satisfies `check`, for arguments that are only partly known.
fn Mock2[A, B, R].expect_called_matching(
	check: fn(Call2[A, B]) Bool,
	site: String = caller_site()
) Void!:
	for call in self.calls:
		if check(call): return ok()
	return fail(f"no call matched, got {repr(self.calls)}", site)

// The arguments of one call to a `Mock3`.
export type Call3[A: Clonable & Equal, B: Clonable & Equal, C: Clonable & Equal]:
	// Argument 1 of the call.
	a: A
	// Argument 2 of the call.
	b: B
	// Argument 3 of the call.
	c: C

// A mock of a function taking 3 arguments and returning R: records calls and answers
// from rules, a queue, then the fallback.
export type Mock3[
	A: Clonable & Equal,
	B: Clonable & Equal,
	C: Clonable & Equal,
	R: Clonable,
]:
	// The answer when no rule or queued answer applies.
	fallback: R
	// One entry per call, oldest first.
	calls: List[Call3[A, B, C]] = []
	// Answers queued by `returns_once`, in order.
	queue: List[R] = []
	// How many queued answers have been used.
	used: Int = 0
	// The arguments of each `returns_for` rule, parallel to `rule_answers`.
	rule_args: List[Call3[A, B, C]] = []
	// The answer of each `returns_for` rule; the first matching rule wins.
	rule_answers: List[R] = []

// Records the call and answers: the first matching rule, else the next queued value,
// else the fallback.
fn var Mock3[A, B, C, R].call(a: A, b: B, c: C) R:
	self.calls.append(Call3[A, B, C](a.clone(), b.clone(), c.clone()))
	for i in 0..self.rule_args.length():
		if self.rule_args[i] == Call3[A, B, C](a.clone(), b.clone(), c.clone()): return (
			self
			.rule_answers[i]
			.clone()
		)

	if self.used < self.queue.length():
		answer := self.queue[self.used].clone()
		self.used += 1
		return answer

	return self.fallback.clone()

// Queues an answer to be used once, before the fallback.
fn var Mock3[A, B, C, R].returns_once(value: R) Void:
	self.queue.append(value)

// Answers `value` whenever called with these arguments, ahead of the queue and the
// fallback.
fn var Mock3[A, B, C, R].returns_for(a: A, b: B, c: C, value: R) Void:
	self.rule_args.append(Call3[A, B, C](a.clone(), b.clone(), c.clone()))
	self.rule_answers.append(value)

// Forgets recorded calls, queued answers and rules; the fallback stays.
fn var Mock3[A, B, C, R].reset() Void:
	self.calls = []
	self.queue = []
	self.used = 0
	self.rule_args = []
	self.rule_answers = []

// Fails unless called exactly `times` times.
fn Mock3[A, B, C, R].expect_called_times(times: Int, site: String = caller_site()) Void!:
	if self.calls.length() == times: return ok()
	return fail(f"expected {times} calls, got {self.calls.length()}", site)

// Fails when called at all.
fn Mock3[A, B, C, R].expect_not_called(site: String = caller_site()) Void!:
	return self.expect_called_times(0, site)

// Fails while queued answers from `returns_once` remain unused.
fn Mock3[A, B, C, R].expect_answers_used(site: String = caller_site()) Void!:
	if self.used == self.queue.length(): return ok()
	return fail(
		f"{self.queue.length() - self.used} queued answers were never used",
		site,
	)

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

// Fails unless some call satisfies `check`, for arguments that are only partly known.
fn Mock3[A, B, C, R].expect_called_matching(
	check: fn(Call3[A, B, C]) Bool,
	site: String = caller_site()
) Void!:
	for call in self.calls:
		if check(call): return ok()
	return fail(f"no call matched, got {repr(self.calls)}", site)
