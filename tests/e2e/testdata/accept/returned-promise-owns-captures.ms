import (
	expect_equal from "@std/test/test.ms",
	Promise, promise from "@std/concurrency/promise.ms",
)

type Target:
	host: String
	port: Int

fn length_of(address: String) Int!:
	return ok(address.length())

fn port_of(target: Target) Int!:
	return ok(target.port + target.host.length())

fn start(address: String) Promise[Int]:
	return promise(fn: length_of(address))

fn start_local() Promise[Int]:
	text := "local"
	return promise(fn: length_of(text))

fn start_target(target: Target) Promise[Int]:
	return promise(fn: port_of(target))

test "a returned promise owns the parameter it captures":
	address := "localhost"
	p := start(address.clone())
	try expect_equal(try p.wait(), 9)
	try expect_equal(address.length(), 9)

test "a returned promise owns a local it captures":
	p := start_local()
	try expect_equal(try p.wait(), 5)

test "a returned promise owns an aggregate it captures":
	p := start_target(Target("host", 80))
	try expect_equal(try p.wait(), 84)

test "dropping an unwaited returned promise ends it":
	_p := start("dropped")
