import expect_equal from "@std/test/test.ms"

fn failed_value() Int!:
	return error(Error("expected-default-error"))

fn stopped(var values: List[Int], extra: Int = try failed_value()) Int!:
	return ok(values.length() + extra)

fn call_default() Int!:
	var values = [1]
	return stopped(var values)

test "a failed default releases its earlier var copy":
	try expect_equal(call_default().is_error(), true)

fn default_count(values: List[Int]) Int!:
	if values.length() > 1: return error(Error("default-error"))

	return ok(values.length())

fn recursive(var values: List[Int], remaining: Int = try default_count(values)) Int!:
	if remaining == 0: return ok(values.length())

	values.append(2)
	return recursive(var values)

fn invoke() Int!:
	var values = [1]
	return recursive(var values, 1)

test "recursive omitted default retains caller var binding":
	try expect_equal(invoke().is_error(), true)

fn grow(var values: List[Int]) Int:
	values.append(9)
	return values.length()

fn changed(var values: List[Int], extra: Int = grow(var values)) Int:
	return values.length() * 10 + extra

test "a default that changes an earlier var keeps its change":
	var values = [1]
	try expect_equal(changed(var values), 22)
	try expect_equal(values.length(), 2)
