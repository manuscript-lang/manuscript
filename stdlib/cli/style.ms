/*
Terminal text styling and measuring: colors, attributes, and width-aware helpers for strings that carry escape sequences.

`paint(text, style, colors)` wraps `text` in the SGR sequences for a `Style` and resets afterwards. `colors` is the count from `terminal_capabilities().colors`: 0 returns `text` unchanged, 16 and 256 downgrade richer colors to the nearest available one. `styled` reads the count itself. `strip_ansi` removes escape sequences, `visible_width` counts the columns a string occupies on screen, and `wrap_text` breaks text into rows of at most a width, carrying the active style across breaks.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Color, Style, paint, visible_width from "@std/cli/style.ms"

fn main() Unit!:
    warning := Style(foreground: Color.Ansi(3), bold: true)
    text := paint("careful", warning, 16)
    width := visible_width(text)?
    print("{width}")
```
*/
import (
	terminal_capabilities from "@std/cli/terminal.ms",
	Regex, compile from "@std/string.ms",
)

// A terminal color: the terminal default, a 16-color index, a 256-color palette index,
// or a 24-bit RGB value. `paint` downgrades richer colors to what the terminal
// supports.
export enum Color:
	// The terminal's own default color, which emits no color sequence.
	Default
	// One of the 16 ANSI colors; values outside 0 to 15 are clamped.
	Ansi(
		// 0 to 7 normal colors, 8 to 15 bright colors.
		index: Int
	)
	// An entry of the 256-color palette; values outside 0 to 255 are clamped, and
	// terminals below 256 colors get the nearest of 16.
	Indexed(
		// 0 to 255 in the 256-color palette.
		index: Int
	)
	// A 24-bit color; terminals below 16777216 colors get the nearest palette entry.
	Rgb(
		// Red, 0 to 255.
		red: Int,
		// Green, 0 to 255.
		green: Int,
		// Blue, 0 to 255.
		blue: Int
	)

// Colors and attributes of a run of text.
export type Style:
	// Text color; `Color.Default` leaves the terminal's own foreground.
	foreground: Color = Color.Default
	// Background color; `Color.Default` leaves the terminal's own background.
	background: Color = Color.Default
	// Heavier weight when true; defaults to false.
	bold: Bool = false
	// Reduced intensity when true; defaults to false.
	dim: Bool = false
	// Slanted text when true; defaults to false.
	italic: Bool = false
	// Underlined text when true; defaults to false.
	underline: Bool = false
	// Swaps foreground and background when true; defaults to false.
	reverse: Bool = false
	// Struck-through text when true; defaults to false.
	strikethrough: Bool = false

esc := "\u{1b}"
csi_final := "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"

fn clamp(value: Int, low: Int, high: Int) Int:
	if value < low: return low
	if value > high: return high

	return value

// The 256-color index nearest to an RGB color: the 6x6x6 cube or the gray ramp,
// whichever is closer.
fn rgb_to_indexed(red: Int, green: Int, blue: Int) Int:
	levels := [0, 95, 135, 175, 215, 255]

	fn nearest(value: Int) Int:
		var best = 0
		var i = 1

		while i < 6:
			if (levels[i] - value).abs() < (levels[best] - value).abs(): best = i
			i += 1

		return best

	r := nearest(red)
	g := nearest(green)
	b := nearest(blue)
	cube := 16 + 36 * r + 6 * g + b
	average := (red + green + blue) / 3
	gray := clamp((average - 8 + 5) / 10, 0, 23)
	gray_level := 8 + 10 * gray
	cube_error := (
		(levels[r] - red).abs()
		+ (levels[g] - green).abs()
		+ (levels[b] - blue).abs()
	)
	gray_error := (
		(gray_level - red).abs()
		+ (gray_level - green).abs()
		+ (gray_level - blue).abs()
	)
	if gray_error < cube_error: return 232 + gray

	return cube

// The 16-color index nearest to a 256-color palette index.
fn indexed_to_ansi(index: Int) Int:
	if index < 16: return index

	var red = 0
	var green = 0
	var blue = 0

	if index >= 232:
		level := 8 + 10 * (index - 232)
		red = level
		green = level
		blue = level
	else:
		cube := index - 16
		steps := [0, 95, 135, 175, 215, 255]
		red = steps[cube / 36]
		green = steps[(cube / 6) % 6]
		blue = steps[cube % 6]

	brightest := if red > green: red else: green
	peak := if brightest > blue: brightest else: blue
	bright := if peak > 200: 8 else: 0
	hi := if red > 127: 1 else: 0
	hg := if green > 127: 2 else: 0
	hb := if blue > 127: 4 else: 0
	return bright + hi + hg + hb

// The SGR parameters selecting `color`, `base` being 30 for foreground and 40 for
// background.
fn color_codes(color: Color, base: Int, colors: Int) String:
	match color:
		Default: return ""
		Ansi(index):
			i := clamp(index, 0, 15)
			if i < 8: return "{base + i}"

			return "{base + 60 + i - 8}"
		Indexed(index):
			i := clamp(index, 0, 255)
			if colors >= 256: return "{base + 8};5;{i}"

			return color_codes(Color.Ansi(indexed_to_ansi(i)), base, colors)
		Rgb(red, green, blue):
			r := clamp(red, 0, 255)
			g := clamp(green, 0, 255)
			b := clamp(blue, 0, 255)
			if colors >= 16777216: return "{base + 8};2;{r};{g};{b}"

			return color_codes(Color.Indexed(rgb_to_indexed(r, g, b)), base, colors)

// The escape sequence that starts `style` for a terminal with `colors` colors, or ""
// when it changes nothing.
export fn style_start(style: Style, colors: Int) String:
	if colors <= 0: return ""

	var codes = List[String]()
	if style.bold: codes.append("1")
	if style.dim: codes.append("2")
	if style.italic: codes.append("3")
	if style.underline: codes.append("4")
	if style.reverse: codes.append("7")
	if style.strikethrough: codes.append("9")

	foreground := color_codes(style.foreground, 30, colors)
	background := color_codes(style.background, 40, colors)
	if not foreground.is_empty(): codes.append(foreground)
	if not background.is_empty(): codes.append(background)
	if codes.is_empty(): return ""

	return "{esc}[{codes.join(";")}m"

// Wraps `text` in `style` and a reset. Returns `text` unchanged when `colors` is 0 or
// the style is plain.
export fn paint(text: String, style: Style, colors: Int) String:
	start := style_start(style, colors)
	if start.is_empty() or text.is_empty(): return text.clone()

	return "{start}{text}{esc}[0m"

// Like `paint`, using the color count of the current terminal.
// ms: effect std.console.read
export fn styled(text: String, style: Style) String:
	return paint(text, style, terminal_capabilities().colors)

fn escape_pattern() Regex:
	// CSI sequences, OSC sequences ending in BEL or ST, and two-byte escapes.
	pattern := "{esc}\\[[0-?]*[ -/]*[@-~]|{esc}\\][^\u{7}{esc}]*(\u{7}|{esc}\\\\)|{esc}[@-Z\\\\-_]"
	return compile(pattern).get(none)

// Removes escape sequences from `text`.
export fn strip_ansi(text: String) String:
	if not text.contains(esc): return text.clone()
	return escape_pattern().replace_all(text, "").get(text.clone())

// The number of terminal columns `text` occupies, ignoring escape sequences.
export fn visible_width(text: String) Int!:
	return strip_ansi(text).display_width()

fn char_width(c: String) Int:
	return c.display_width().get(1)

/*
Splits `text` on newlines and wraps each line into rows of at most `width` columns, counting only visible
characters. Escape sequences stay with the text they style: a row that breaks inside styled text ends with a
reset and the next row repeats the active sequences. A `width` below 1 is treated as 1.
*/
export fn wrap_text(text: String, width: Int) List[String]:
	room := if width < 1: 1 else: width
	var out = List[String]()

	for line in text.split("\n"):
		var row = ""
		var used = 0
		var active = ""
		var sequence = ""
		var in_sequence = false

		for c in line.chars():
			if in_sequence:
				sequence = "{sequence}{c}"

				if csi_final.contains(c) and sequence.length() > 2 or c == "\u{7}":
					in_sequence = false
					row = "{row}{sequence}"

					if sequence == "{esc}[0m" or sequence == "{esc}[m":
						active = ""
					else:
						active = "{active}{sequence}"

				continue

			if c == esc:
				in_sequence = true
				sequence = c.clone()
				continue

			w := char_width(c)

			if used + w > room and used > 0:
				suffix := if active.is_empty(): "" else: "{esc}[0m"
				out.append("{row}{suffix}")
				row = active.clone()
				used = 0

			row = "{row}{c}"
			used += w

		out.append(row)

	return out

// Cuts the single line `text` to at most `width` visible columns, keeping escape
// sequences and ending a styled cut with a reset.
export fn truncate_text(text: String, width: Int) String:
	rows := wrap_text(text, width)
	if rows.is_empty(): return ""

	return rows[0].clone()
