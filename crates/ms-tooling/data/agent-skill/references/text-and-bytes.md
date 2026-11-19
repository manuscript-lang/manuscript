# Text and bytes

`String` is immutable UTF-8; `Bytes` (`@std/bytes.ms`) is raw data. Converting bytes to text can fail.

- **Offsets are bytes.** `length()` counts bytes (`"é"` is 2); `slice`, `index_of`, `scalar_at` take byte offsets, and `slice` faults inside a character. No `text[i]`. Walk with `chars()` or `scalars(s)` (`@std/text.ms`); `scalar_length()` counts characters, `display_width()` columns.
- **Literals.** `"plain"` never interpolates; `f"x {n}"` does (`\{` `\}` for braces; plain quotes inside `{}`); `r"\d+"` is raw; `"""`/`r"""` open multi-line text (opening quotes end their line, closing quotes stand alone).
- **Bytes.** `to_bytes()`, `as_bytes()`; `decode_utf8()` returns `String?`. Printing Bytes shows numbers: decode first. Read a file: `read_file(path).wait()?.decode_utf8().ok_or(Error("not UTF-8"))?`. Iterate with `values(bytes)`.
- **Text work.** `split`, `split_once`, `lines`, `fields`, `trim`, `cut_prefix`, `replace`, `pad_start`; build with `StringBuilder` (`@std/string_builder.ms`), not repeated `concat`.
- **Parsing.** `parse_int()`/`parse_float()` return Optionals: `.ok_or(Error(f"bad number: {s}", kind: "EINVAL"))?`. Structured text: `@std/data/json.ms` (`parse[T]`, `stringify`), `csv`, `toml`, `yaml`, `@std/regex.ms`, `@std/net/url.ms`.

<!-- complete: text-bytes.ms -->
```manuscript
fn first_word(line: String) String:
	trimmed := line.trim()
	if cut := trimmed.index_of(" "): return trimmed.slice(0, cut)

	return trimmed

fn describe(text: String) String:
	return f"{text.length()} bytes, {text.scalar_length()} characters, first word '{first_word(text)}'"

fn main() Void!:
	print(describe("héllo wörld"))

	raw := "héllo".to_bytes()
	text := raw.decode_utf8().ok_or(Error("not UTF-8", kind: "EBADMSG"))?
	print(f"{raw.length()} raw bytes decode to {text}")
```
