import (
	panic from "@std/core.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

fn optional(value: Int) Int?: return value

fn result(value: Int) Int!: return ok(value)

fn then_branch() Int:
	while true:
		if panic("stop"): break

fn else_branch() Int:
	while true:
		if panic("stop"):
			continue
		else:
			break

fn optional_then_branch() Int:
	while true:
		if _value := optional(panic("stop")): break

fn optional_else_branch() Int:
	while true:
		if _value := optional(panic("stop")):
			continue
		else:
			break

fn nested_loop() Int:
	while true:
		while true:
			break
		if panic("stop"): break

fn callback() Int:
	f: fn() Int := fn() Int:
		while true:
			if panic("stop"): break
	return f()

fn result_branch() Int:
	while true:
		if _value := result(panic("stop")): break

test "nonreturning conditions cannot reach branch breaks":
	then_branch_fault := expect_fault(
		fn:
			_ := then_branch()
	)?
	expect_contains(then_branch_fault, "stop")?

	else_branch_fault := expect_fault(
		fn:
			_ := else_branch()
	)?
	expect_contains(else_branch_fault, "stop")?

	optional_then_branch_fault := expect_fault(
		fn:
			_ := optional_then_branch()
	)?
	expect_contains(optional_then_branch_fault, "stop")?

	optional_else_branch_fault := expect_fault(
		fn:
			_ := optional_else_branch()
	)?
	expect_contains(optional_else_branch_fault, "stop")?

	nested_loop_fault := expect_fault(
		fn:
			_ := nested_loop()
	)?
	expect_contains(nested_loop_fault, "stop")?

	callback_fault := expect_fault(
		fn:
			_ := callback()
	)?
	expect_contains(callback_fault, "stop")?

	result_branch_fault := expect_fault(
		fn:
			_ := result_branch()
	)?
	expect_contains(result_branch_fault, "stop")?
