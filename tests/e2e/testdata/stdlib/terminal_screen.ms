import (
	Screen, new_screen from "@std/cli/screen.ms",
	expect_equal from "@std/test/test.ms",
)

esc := "\u{1b}"
begin := "{esc}[?2026h"
end := "{esc}[?2026l"

fn screen(height: Int) Screen:
	var s = new_screen()
	s.resize(height)
	return s

test "the first draw writes every row and parks the cursor":
	var s = screen(24)
	out := s.render(["> hi", "status"], 0, 4)
	try expect_equal(
		out,
		"{begin}\r{esc}[2K> hi\r\n{esc}[2Kstatus{esc}[J{esc}[1A\r{esc}[4C{end}",
	)

test "an unchanged frame rewrites only the cursor":
	var s = screen(24)
	rows := ["one", "two", "three"]
	_ := s.render(rows.clone(), 2, 0)
	out := s.render(rows.clone(), 2, 3)
	try expect_equal(out, "{begin}\r{esc}[J\r{esc}[3C{end}")

test "a changed row rewrites from that row down":
	var s = screen(24)
	_ := s.render(["one", "two", "three"], 2, 0)
	out := s.render(["one", "TWO", "three"], 2, 0)
	try expect_equal(out, "{begin}{esc}[1A\r{esc}[2KTWO\r\n{esc}[2Kthree{esc}[J\r{end}")

test "new rows are added below the last one":
	var s = screen(24)
	_ := s.render(["one"], 0, 0)
	out := s.render(["one", "two"], 1, 0)
	try expect_equal(out, "{begin}\r\r\n{esc}[2Ktwo{esc}[J\r{end}")

test "a changed row above the viewport clears the screen and scrollback":
	var s = screen(2)
	_ := s.render(["a", "b", "c", "d"], 3, 0)
	out := s.render(["A", "b", "c", "d"], 3, 0)
	try expect_equal(out.contains("{esc}[2J{esc}[3J{esc}[H{esc}[2KA\r\n"), true)

test "reset forgets the previous frame":
	var s = screen(24)
	_ := s.render(["one", "two"], 1, 0)
	s.reset()

	out := s.render(["one", "two"], 1, 0)
	try expect_equal(out.contains("{esc}[2Kone"), true)
