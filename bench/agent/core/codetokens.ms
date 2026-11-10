// Count lexical tokens in the source an agent produced (language-neutral, dependency-free).
//
// A token is an identifier or keyword, a number, a string literal, or one punctuation/operator character.
// Comments are excluded. This is a size measure of the final program, not any model's tokenizer count.
import (
	compile from "@std/string.ms",
	glob, GlobOptions from "@std/os/fs.ms",
	read_text from "../lib/text.ms",
)

SKIP_DIRS := [
	"target", "node_modules", ".bench", "docs", "examples", ".git", "vendor",
	".ms-cache"
]

// Lexical tokens in `text` once `//` and `/* */` comments are removed.
export fn count_text(text: String) Int:
	comments := compile("//[^\n]*|(?s)/\\*.*?\\*/").get()
	token := compile(
		"\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`[^`]*`|[A-Za-z_]\\w*|\\d[\\w.]*|[^\\s\\w]"
	).get()
	bare := comments.replace_all(text, " ", none).get(text)
	return token.find_all(bare, none).get([]).length()

// Tokens over every `*suffix` file under `root`, skipping build output and the bundled docs.
export fn count_workspace(root: String, suffix: String) Int:
	var total = 0

	for entry in glob(root, GlobOptions(patterns: ["**/*{suffix}"])).get([]):
		path := entry.path.clone()
		parts := path.split("/")
		dirs := parts.take(parts.length() - 1)
		if dirs.any(fn d: SKIP_DIRS.contains(d)): continue

		total += count_text(read_text("{root}/{path}"))

	return total
