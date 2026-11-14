// Regular expressions over generated log text: find_all, captures, replace_all and
// split.
import (
	compile from "@std/regex.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

fn make_text(lines: Int) String:
	var sb = StringBuilder()
	var x = 9

	for i in 0..lines:
		x = lcg(x)
		sb.append(
			"user{x % 5000}@host{x / 3 % 90}.com 10.{x % 256}.{x / 5 % 256}.{x / 7 % 256} GET /api/v{x % 4}/items/{x / 11 % 100000} {200 + x % 3 * 100} took {x % 900}ms\n"
		)

	return sb.build()

fn main() Unit:
	text := make_text(120000)
	emails := compile("[a-z]+[0-9]*@[a-z]+[0-9]*\\.com").get()
	ips := compile("([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)").get()
	times := compile("took ([0-9]+)ms").get()
	versions := compile("/api/v[0-9]/").get()
	email_count := emails.find_all(text, none).get().length()
	var octet_total = 0
	for m in ips.captures_all(text, none).get():
		octet_total += m[4].parse_int().get(0)

	var took_total = 0
	for m in times.captures_all(text, none).get():
		took_total += m[1].parse_int().get(0)

	masked := ips.replace_all(text, "x.x.x.x", none).get()
	versions_found := versions.find_all(text, none).get().length()
	pieces := compile(" +").get().split(text, none).get().length()
	print(
		"emails {email_count} octets {octet_total} took {took_total} masked {masked.length()} versions {versions_found} pieces {pieces}"
	)
