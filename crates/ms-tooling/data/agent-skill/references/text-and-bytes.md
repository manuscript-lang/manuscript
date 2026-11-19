# Text and bytes

`String` is immutable, always valid UTF-8, and needs no import. `Bytes` is immutable raw data from `@std/bytes.ms`. They are different types: converting is explicit, and converting bytes to text can fail.

## Lengths and offsets are bytes

There is no `text[i]` and no integer index of characters. `s.length()` is the **byte** count (constant time); `slice(a, b)`, `view`, `index_of`, `last_index_of` and `scalar_at` all take **byte offsets**, so a position from one can be passed to another. `"é"` has length 2. `scalar_length()` counts Unicode scalars in linear time; graphemes are not supported.

- Walk characters: `for c in s.chars():` (each is a one-character String), or `scalars(s)` from `@std/text.ms` for code points.
- Compare ASCII or compare whole strings; do not assume a column equals a byte. `s.slice(a, b)` is a plain String that faults if an offset splits a character; offsets from `index_of` are safe.
- Pad and align with `pad_start(width, " ")` / `pad_end`; width counts bytes, `display_width()` measures terminal columns.
- Split and trim with `split`, `split_once` (`SplitParts?`), `lines`, `fields` (whitespace), `trim`, `cut_prefix`, `cut_suffix`; change case with `upper`, `lower`; replace with `replace`.

## Literals

- `"plain"` never interpolates; braces are ordinary (`"{\"a\": 1}"`). `f"total {n}"` interpolates; write `\{` `\}` for literal braces inside `f` text. Inside `{}` write quotes plainly: `f"{xs.join(", ")}"`.
- `r"\d+"` is raw (no escapes). `"""` and `r"""` open multi-line text: the opening quotes end their line, the closing quotes stand alone, and the closing indentation is removed from every line. Use `r"""` for JSON and regex fixtures.
- Escapes: `\n \r \t \" \\ \u{1F642}`. There are no byte or character literals.
- Anything converts to text with `to_string()` or interpolation. Declare `fn T.to_string() String` on your type to change how it prints and interpolates.

## Bytes

- `text.to_bytes()` and `text.as_bytes()` make Bytes; `bytes.decode_utf8()` returns `String?`, absent when invalid. **Printing Bytes shows numbers, not text**: `print(bytes)` renders `Bytes(104, 105)`; `bytes.to_string()` is a lint warning. Always decode first.
- Files, sockets and processes hand you Bytes. Reading a text file is `read_file(path).wait()?.decode_utf8().ok_or(Error("not UTF-8"))?`. Writing is `write_file(path, text.to_bytes())`.
- Iterate bytes with `for b in values(bytes):` (`values` from `@std/bytes.ms`). Build with `BytesBuilder`; build text with `StringBuilder` from `@std/string_builder.ms` rather than `s = s.concat(...)` in a long loop.
- Binary encodings are in `@std/data/encoding.ms` (`hex_encode`, `base64_encode`, ...), checksums in `@std/data/checksum.ms`, hashes in `@std/crypto/crypto.ms`.

## Parsing text into values

`s.parse_int()` and `parse_float()` return Optionals: turn them into errors with `.ok_or(Error(f"bad number: {s}", kind: "EINVAL"))?`. For structured text use `@std/data/json.ms` (`parse[T](text)` and `stringify`), `csv.ms`, `toml.ms`, `yaml.ms`, `@std/regex.ms`, `@std/net/url.ms` rather than hand-parsing.

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

The first line prints `13 bytes, 11 characters, first word 'héllo'`: length counts bytes, `scalar_length` counts characters.
