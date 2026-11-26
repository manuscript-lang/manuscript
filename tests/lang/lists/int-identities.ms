// conform: tags=control-flow,formatter,lists,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/int-identities.ms
import expect_equal, expect_true from "@std/test/test.ms"

fn touch(var log List[Int], value Int) Int {
	log.append(value)
	return value
}

test "identities keep boundaries" {
	for x in [-9223372036854775808, 9223372036854775807, -7, 0, 1] {
		((x + 0 == x)) | expect_true?
		((0 + x == x)) | expect_true?
		((x - 0 == x)) | expect_true?
		((x * 0 == 0)) | expect_true?
		((0 * x == 0)) | expect_true?
		((x * 1 == x)) | expect_true?
		((1 * x == x)) | expect_true?
		((x / 1 == x)) | expect_true?
		((x % 1 == 0)) | expect_true?
	}
}

test "identities keep operand effects" {
	var log List[Int] = []
	((touch(log, 1) * 0 == 0)) | expect_true?
	((0 * touch(log, 2) == 0)) | expect_true?
	((touch(log, 3) * 1 == 3)) | expect_true?
	((1 * touch(log, 4) == 4)) | expect_true?
	((touch(log, 5) + 0 == 5)) | expect_true?
	((0 + touch(log, 6) == 6)) | expect_true?
	((touch(log, 7) - 0 == 7)) | expect_true?
	((touch(log, 8) / 1 == 8)) | expect_true?
	((touch(log, 9) % 1 == 0)) | expect_true?
	log | expect_equal([1, 2, 3, 4, 5, 6, 7, 8, 9])?
}
// expect-exit: 0
// expect-tests: passed=2 failed=0
