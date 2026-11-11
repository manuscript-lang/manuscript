import expect_equal from "@std/test/test.ms"

type Item:
	case: Int

enum PayloadKeyword:
	case(value: Int)

enum NullaryKeyword:
	case

fn case(value: Int) Int: value + 1

fn present(value: Int?) Int:
	match value:
		case: return case
		none: return 0

test "case is an ordinary identifier in declarations and patterns":
	expect_equal(case(7), 8)?

	case := 3
	item := Item(case: case)
	expect_equal(item.case, 3)?

	value := PayloadKeyword.case(9)

	match value:
		case(number): expect_equal(number, 9)?

	flag := NullaryKeyword.case

	match flag:
		case: expect_equal(case, 3)?

	expect_equal(present(7), 7)?
	expect_equal(present(none), 0)?
