// ms: allow_effect std.fs.read

// Count lexical tokens in the source an agent produced (language-neutral,
// dependency-free).
//
// A token is an identifier or keyword, a number, a string literal, or one
// punctuation/operator character. Comments are excluded. This is a size measure of the
// final program, not any model's tokenizer count.
import (
	GlobOptions, glob from "@std/os/fs.ms",
	compile from "@std/regex.ms",

	read_text from "../lib/text.ms",
)

SKIP_DIRS := [
	"target", "node_modules", ".bench", ".claude", "docs", "examples", ".git", "vendor",
	".ms-cache"
]

// Lexical tokens in `text` once `//` and `/* */` comments are removed.
export fn count_text(text String) Int {
	comments := compile("//[^\n]*|(?s)/\\*.*?\\*/").get()
	token := compile(
		"\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`[^`]*`|[A-Za-z_]\\w*|\\d[\\w.]*|[^\\s\\w]"
	).get()
	bare := comments.replace_all(text, " ", null).get_or(text.clone().clone())
	return token.find_all(bare, null).get_or([]).length()
}

// Tokens over every `*suffix` file under `root`, skipping build output and the bundled
// docs.
export fn count_workspace(root, suffix String) Int {
	var total = 0

	for entry in glob(root, GlobOptions(patterns: [f"**/*{suffix}"])).get_or([]) {
		path := entry.path.clone()
		parts := path.split("/").collect()
		dirs := parts.take(parts.length() - 1)
		if dirs.any(d => SKIP_DIRS.contains(d)) { continue }

		total += count_text(read_text(f"{root}/{path}"))
	}

	return total
}
