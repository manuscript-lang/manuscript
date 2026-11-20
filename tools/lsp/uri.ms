// `file:` URIs and the paths they name, as crates/ms-lsp/src/uri.rs reads them. Only
// the shapes editors send are handled: `file:///path`, percent escapes, and a Windows
// drive written `/D:/dir`.
import (
	decode_component from "@std/net/url.ms",
	expect_equal from "@std/test/test.ms",
)

// Whether `uri` names a file on disk.
export fn is_file(uri: String) Bool: uri.lower().starts_with("file:")

// The path a `file:` URI names; any other URI is its own name.
export fn filename(uri: String) String:
	if not is_file(uri): return uri.clone()

	rest := uri.slice(5, uri.length())
	var path = rest.clone()

	if hosted := rest.cut_prefix("//"):
		slash := hosted.index_of("/")
		if slash.is_none(): return ""

		host := hosted.slice(0, slash.get())
		path = hosted.slice(slash.get(), hosted.length())
		if not host.is_empty() and host != "localhost": path = f"//{host}{path}"

	decoded := decode_component(path).get_or(path)
	bytes := decoded.as_bytes()

	// `/D:/dir` is the Windows spelling of `D:/dir`.
	if (
		bytes.length() >= 3
		and bytes.get(0) == 47
		and bytes.get(2) == 58
		and decoded.slice(1, 2).upper() != decoded.slice(1, 2).lower()
	):
		return decoded.slice(1, decoded.length())

	return decoded

fn keeps(ch: String) Bool:
	scalar := ch.scalar_at(0)
	if scalar >= 48 and scalar <= 57: return true
	if scalar >= 65 and scalar <= 90: return true
	if scalar >= 97 and scalar <= 122: return true

	return "-_.~$&+,/:;=@".contains(ch)

// The `file:` URI of an absolute path.
export fn file_uri(path: String) String:
	var unix = path.replace("\\", "/")
	if not unix.starts_with("/"): unix = f"/{unix}"

	var out = "file://"

	for ch in unix.chars():
		if keeps(ch):
			out = out.concat(ch)
		else:
			for raw in ch.as_bytes().values():
				byte := raw.to_int()
				digits := "0123456789ABCDEF"
				out = out.concat("%").concat(
					digits.slice(byte / 16, byte / 16 + 1)
				).concat(digits.slice(byte % 16, byte % 16 + 1))

	return out

test "a file URI decodes its escapes":
	expect_equal(filename("file:///tmp/a%20b.ms"), "/tmp/a b.ms")?
	expect_equal(filename("file:///C:/dir/x.ms"), "C:/dir/x.ms")?
	expect_equal(filename("untitled:Untitled-1"), "untitled:Untitled-1")?

test "a path becomes a file URI":
	expect_equal(file_uri("/tmp/a b.ms"), "file:///tmp/a%20b.ms")?
	expect_equal(file_uri("/tmp/é.ms"), "file:///tmp/%C3%A9.ms")?
