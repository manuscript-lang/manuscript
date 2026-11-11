// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Label:
	text: String

enum Outcome[T = Int]:
	Success(value: T)
	Failure

fn Outcome[T].succeeded() Bool:
	return match self:
		Success(_): true
		Failure: false

fn score(value: Outcome[Int]) Int:
	return match value:
		Success(number): number
		Failure: -1

test "enum cases retain payload construction and exhaustive matching":
	success: Outcome := Success(7)
	failure := Outcome[Int].Failure
	expect_equal(score(success), 7)?
	expect_equal(score(failure), -1)?
	expect_equal(success.succeeded(), true)?
	expect_equal(failure.succeeded(), false)?

	named := Outcome[Label].Success(Label("ready"))

	match named:
		Success(label): expect_equal(label.text, "ready")?
		Failure: expect_equal(false, true)?
