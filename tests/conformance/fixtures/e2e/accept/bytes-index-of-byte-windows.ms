// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "index_of_byte agrees with a scan across the inline window and the runtime":
	text := "abc,defghijklmnopqrstuvwxyz,\n0123456789012345678901234567890,x"
	b := text.to_bytes()
	var found = List[Int]()
	var at = 0

	while true:
		if i := b.index_of_byte(44, at):
			found.append(i)
			at = i + 1
		else: break

	expect_equal(found, [3, 27, 60])?
	expect_equal(b.index_of_byte(10, 0).get(-1), 28)?
	expect_equal(b.index_of_byte(120, -5).get(-1), 24)?
	expect_equal(b.index_of_byte(122, 0).get(-1), 26)?
	expect_equal(b.index_of_byte(255, 0).get(-1), -1)?
	expect_equal(b.index_of_byte(44, 100).get(-1), -1)?
	expect_equal(b.index_of_byte(120, 62).get(-1), -1)?
	expect_equal("short".to_bytes().index_of_byte(116, 0).get(-1), 4)?
	expect_equal("".to_bytes().index_of_byte(0, 0).get(-1), -1)?
	expect_equal("0123456789abcdefg".to_bytes().index_of_byte(103, 0).get(-1), 16)?
	expect_equal("0123456789abcdef".to_bytes().index_of_byte(102, 0).get(-1), 15)?
	expect_equal("0123456789abcdef".to_bytes().index_of_byte(102, 1).get(-1), 15)?
