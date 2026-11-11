// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Color,
	Style,
	paint,
	strip_ansi,
	style_start,
	truncate_text,
	visible_width,
	wrap_text from "@std/cli/style.ms",
	expect_equal from "@std/test/test.ms",
)

esc := "\u{1b}"

test "paint wraps text in the style and a reset":
	warning := Style(foreground: Color.Ansi(3), bold: true)
	expect_equal(paint("careful", warning, 16), "{esc}[1;33mcareful{esc}[0m")?
	expect_equal(
		paint("x", Style(background: Color.Ansi(9)), 16),
		"{esc}[101mx{esc}[0m",
	)?
	expect_equal(
		paint("x", Style(underline: true, italic: true, reverse: true), 16),
		"{esc}[3;4;7mx{esc}[0m",
	)?

test "paint adds nothing without colors, without a style, or without text":
	expect_equal(paint("plain", Style(bold: true), 0), "plain")?
	expect_equal(paint("plain", Style(), 16777216), "plain")?
	expect_equal(paint("", Style(bold: true), 16), "")?
	expect_equal(style_start(Style(bold: true), 0), "")?

test "rgb and palette colors downgrade to what the terminal supports":
	pink := Style(foreground: Color.Rgb(255, 0, 255))
	expect_equal(paint("a", pink, 16777216), "{esc}[38;2;255;0;255ma{esc}[0m")?
	expect_equal(paint("a", pink, 256), "{esc}[38;5;201ma{esc}[0m")?
	expect_equal(paint("a", pink, 16), "{esc}[95ma{esc}[0m")?
	expect_equal(
		paint("a", Style(foreground: Color.Indexed(196)), 256),
		"{esc}[38;5;196ma{esc}[0m",
	)?
	expect_equal(
		paint("a", Style(foreground: Color.Indexed(196)), 16),
		"{esc}[91ma{esc}[0m",
	)?
	expect_equal(
		paint("a", Style(background: Color.Rgb(10, 10, 10)), 256),
		"{esc}[48;5;232ma{esc}[0m",
	)?
	expect_equal(
		paint("a", Style(foreground: Color.Indexed(5)), 16),
		"{esc}[35ma{esc}[0m",
	)?

test "strip_ansi removes sequences and keeps text":
	expect_equal(
		strip_ansi("{esc}[1;31mred{esc}[0m and {esc}[2Kplain"),
		"red and plain",
	)?
	expect_equal(strip_ansi("{esc}]2;title\u{7}after"), "after")?
	expect_equal(strip_ansi("no escapes"), "no escapes")?

test "visible_width counts columns, not escape bytes":
	expect_equal(visible_width("{esc}[1mbold{esc}[0m")?, 4)?
	expect_equal(visible_width("日本")?, 4)?

test "wrap_text breaks at the width and carries styles across rows":
	expect_equal(wrap_text("abcdef", 4), ["abcd", "ef"])?
	expect_equal(wrap_text("ab\ncd", 10), ["ab", "cd"])?
	expect_equal(wrap_text("", 5), [""])?
	expect_equal(wrap_text("日本語", 4), ["日本", "語"])?

	styled := "{esc}[31mabcdef{esc}[0m"
	expect_equal(wrap_text(styled, 4), ["{esc}[31mabcd{esc}[0m", "{esc}[31mef{esc}[0m"])?

test "truncate_text keeps the first row":
	expect_equal(truncate_text("hello world", 5), "hello")?
	expect_equal(truncate_text("hi", 5), "hi")?
