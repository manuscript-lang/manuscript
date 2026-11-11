import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_fault, expect_some from "@std/test/test.ms",
)

type Resource:
	id: Int
	path: String

impl Closeable for Resource:
	var fn close() Unit!:
		append_file(self.path, "{self.id},").wait()?
		self.path = "closed"

fn present(path: String, id: Int) Resource?: Resource(id, path.clone())

fn observed(value: Resource?) Bool: value.is_some()

fn mapped(value: Resource?) Int?: value.map(fn item: item.id)

fn generic_map[T, U](value: T?, transform: fn(T) U) U?: value.map(transform)

fn generic_then[T, U](value: T?, transform: fn(T) U?) U?: value.and_then(transform)

fn identity[T](value: T) T: value

fn checked(value: Resource?) Int!:
	if value.is_some(): return error(Error("expected failure"))
	return ok(0)

fn broken(value: Resource?) Unit:
	if value.is_some():
		_invalid := [1].get(3)

fn log_text(path: String) String!:
	bytes := read_file(path).wait()?
	return ok(expect_some(bytes.decode_utf8())?)

fn retained(path: String) Unit!:
	value := identity(present(path, 7))
	expect_equal(log_text(path)?, "")?
	expect_equal(mapped(value), 7)?
	expect_equal(observed(value), true)?
	expect_equal(log_text(path)?, "")?

fn error_exit(path: String) Unit!:
	_value := checked(present(path, 8))?

test "borrowed source helpers close intact owned wrapper temporaries once":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(observed(present(path, 1)), true)?
	expect_equal(mapped(present(path, 2)), 2)?
	expect_equal(generic_map(present(path, 3), fn item: item.id), 3)?
	expect_equal(generic_then(present(path, 4), fn(item: Resource) Int?: item.id), 4)?
	expect_equal(present(path, 5).map(fn item: item.id), 5)?
	expect_equal(observed(none), false)?
	expect_equal(log_text(path)?, "1,2,3,4,5,")?

test "whole borrowed results transfer temporary ownership and named borrows do not close":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	retained(path)?
	expect_equal(log_text(path)?, "7,")?

test "borrowed wrapper temporaries close on expected errors and source faults":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(error_exit(path).is_error(), true)?

	_fault := expect_fault(fn: broken(present(path, 9)))?
	expect_equal(log_text(path)?, "8,9,")?

fn pick(first: Resource?, second: Resource?) Resource?:
	if second.is_some(): return first
	return first

fn transferred_then_faulted(path: String) Unit:
	broken(pick(present(path, 10), present(path, 11)))

fn transfer_first(path: String) Unit!:
	value := pick(present(path, 12), present(path, 13))
	expect_equal(mapped(value), 12)?
	expect_equal(log_text(path)?, "13,")?

test "whole transfer keeps newer argument cleanups active until statement end":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	_fault := expect_fault(fn: transferred_then_faulted(path))?
	expect_equal(log_text(path)?, "10,11,")?
	write_file(path, "", replace: true).wait()?
	transfer_first(path)?
	expect_equal(log_text(path)?, "13,12,")?

fn resource_path(value: Resource?) String: value.get().path

test "borrowed parts are copied before their temporary owner closes":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	saved := resource_path(present(path, 14))
	expect_equal(saved, path)?
	expect_equal(log_text(path)?, "14,")?

fn success(path: String, id: Int) Resource!Int: ok(Resource(id, path.clone()))

fn result_observed(value: Resource!Int) Bool: value.is_ok()

fn branched_transfers(path: String) Unit!:
	for i in 0..3:
		value := if i == 1: identity(identity(present(path, 20 + i))) else: identity(
			present(path, 20 + i)
		)
		expect_equal(mapped(value), 20 + i)?

test "nested whole transfers stay path local across branches and loops":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	branched_transfers(path)?
	expect_equal(result_observed(success(path, 23)), true)?
	expect_equal(log_text(path)?, "20,21,22,23,")?

type ScalarResource:
	id: Int

impl Closeable for ScalarResource:
	var fn close() Unit!: error(Error("scalar resource closed"))

fn scalar_present() ScalarResource?: ScalarResource(1)

fn scalar_observed(value: ScalarResource?) Bool: value.is_some()

fn scalar_observer() Unit:
	_value := scalar_observed(scalar_present())

test "scalar wrapper payloads retain their source-call close obligation":
	_fault := expect_fault(scalar_observer)?

fn extra(value: Resource?, other: Int) Bool: value.is_some() and other == 1

fn number() Int!: ok(1)

test "later successful try preserves source temporary ownership":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(extra(present(path, 30), number()?), true)?
	expect_equal(log_text(path)?, "30,")?

fn named_transferred_fault(path: String) Unit:
	held := identity(present(path, 40))
	broken(held)

test "whole transferred locals retain their fault cleanup":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	_fault := expect_fault(fn: named_transferred_fault(path))?
	expect_equal(log_text(path)?, "40,")?

fn fresh_owner(value: Resource?) Resource?:
	return Resource(51, value.get().path.clone())

fn fresh_then_faulted(path: String) Unit:
	held := fresh_owner(present(path, 50))
	broken(held)

test "retiring a borrowed input does not erase an unrelated result owner":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	_fault := expect_fault(fn: fresh_then_faulted(path))?
	expect_equal(log_text(path)?, "50,51,")?

test "source-reader temporaries finish on each loop condition and short circuit":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	var count = 0

	while count < 4 and observed(present(path, 60 + count)):
		count += 1
		if count == 2: continue
		if count == 4: break

	expect_equal(count, 4)?
	expect_equal(log_text(path)?, "60,61,62,63,")?

fn number_failure() Int!: error(Error("expected operand error"))

fn later_try_fails(path: String) Unit!:
	_value := extra(present(path, 70), number_failure()?)

fn pair_observed(first: Resource?, second: Resource?) Bool:
	return first.is_some() and second.is_some()

fn bad_default() Int: [1].get(3)

fn observes_with_default(value: Resource?, count: Int = bad_default()) Bool:
	return value.is_some() and count > 0

fn default_fault(path: String) Unit:
	_value := observes_with_default(present(path, 82))

test "later argument errors and default faults close acquired wrapper owners":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(later_try_fails(path).is_error(), true)?

	_fault := expect_fault(fn: default_fault(path))?
	expect_equal(log_text(path)?, "70,82,")?

test "named borrowed arguments close in reverse acquisition order":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(
		pair_observed(second: present(path, 80), first: present(path, 81)), true
	)?
	expect_equal(log_text(path)?, "81,80,")?

type FaultyResource:
	path: String

impl Closeable for FaultyResource:
	var fn close() Unit!:
		append_file(self.path, "98,").wait()?
		self.path = "closed"
		return error(Error("expected close failure"))

fn faulty_present(path: String) FaultyResource?: FaultyResource(path.clone())

fn faulty_observed(value: FaultyResource?) Bool: value.is_some()

fn close_fault(path: String) Unit:
	_outer := Resource(99, path.clone())
	_observed := faulty_observed(faulty_present(path))

test "a failed temporary close leaves older lexical cleanup registered":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?

	_fault := expect_fault(fn: close_fault(path))?
	expect_equal(log_text(path)?, "98,99,")?

fn pair(first: Resource?, second: Resource?) Bool:
	return first.is_some() or second.is_some()

fn with_default(value: Resource?, tail: Int = 1) Bool:
	return value.is_some() or tail > 0

type Observer:
	tag: Int

impl Observer:
	fn sees(value: Resource?) Bool: value.is_some()

fn borrowed_conversion_calls(path: String) Unit!:
	named := Resource(120, path.clone())
	expect_equal(observed(named), true)?
	expect_equal(mapped(named), 120)?
	expect_equal(with_default(named), true)?
	expect_equal(Observer(1).sees(named), true)?
	expect_equal(checked(named).is_error(), true)?
	expect_equal(log_text(path)?, "")?
	expect_equal(pair(second: present(path, 121), first: named), true)?
	expect_equal(pair(second: named, first: present(path, 122)), true)?
	expect_equal(log_text(path)?, "121,122,")?
	expect_equal(named.id, 120)?

test "borrowed payload optional conversions do not acquire close duty":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	borrowed_conversion_calls(path)?
	expect_equal(log_text(path)?, "121,122,120,")?

fn no_resource() Resource?!: error(Error("expected"))

fn borrowed_conversion_error(path: String) Unit!:
	named := Resource(123, path.clone())
	_used := pair(named, no_resource()?)

fn borrowed_conversion_fault(path: String) Unit:
	named := Resource(124, path.clone())
	_used := pair(named, present(path, [1].get(3)))

test "borrowed optional transport copies leave fault cleanup with original owner":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	expect_equal(borrowed_conversion_error(path).is_error(), true)?

	_fault := expect_fault(fn: borrowed_conversion_fault(path))?
	expect_equal(log_text(path)?, "123,124,")?

fn optional_identity(value: Resource?) Resource?: value

fn with_borrowed_default(value: Resource?, same: Resource? = value) Bool:
	return value.is_some() or same.is_some()

fn with_faulting_default(value: Resource?, tail: Int = [1].get(3)) Bool:
	return value.is_some() or tail > 0

fn retained_conversion(path: String) Unit!:
	named := Resource(130, path.clone())
	retained := optional_identity(named)
	expect_equal(observed(retained), true)?
	expect_equal(log_text(path)?, "")?

fn borrowed_default_fault(path: String) Unit:
	named := Resource(131, path.clone())
	_used := with_faulting_default(named)

fn named_default_reads(path: String) Unit!:
	named := Resource(132, path.clone())
	expect_equal(with_borrowed_default(named), true)?
	expect_equal(with_borrowed_default(named), true)?
	expect_equal(log_text(path)?, "130,131,")?

test "optional conversion provenance distinguishes retained moves from borrowed defaults":
	directory := temporary("source-wrapper-")?
	path := "{directory.path()}/log"
	write_file(path, "").wait()?
	retained_conversion(path)?

	_fault := expect_fault(fn: borrowed_default_fault(path))?
	named_default_reads(path)?
	expect_equal(log_text(path)?, "130,131,132,")?
