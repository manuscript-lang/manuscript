package msruntime

import (
	"context"
	"encoding/hex"
	"math"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func mustOk[T, E any](t *testing.T, r Result[T, E]) T {
	t.Helper()
	if r.Failed {
		t.Fatalf("unexpected failure: %#v", r.Err)
	}
	return r.Val
}

func mustFail[T, E any](t *testing.T, r Result[T, E], want E) {
	t.Helper()
	if !r.Failed {
		t.Fatalf("expected %#v, got success %#v", want, r.Val)
	}
	if any(r.Err) != any(want) {
		t.Fatalf("error = %#v, want %#v", r.Err, want)
	}
}

func cancelledExec() *Execution {
	c, cancel := context.WithCancel(context.Background())
	cancel()
	return &Execution{Context: c}
}

func wasCancelled(f func()) (ok bool) {
	defer func() {
		_, ok = recover().(cancelled)
	}()
	f()
	return false
}

func jsonLimits(bytes, depth, values Option[int]) Option[*JsonLimits] {
	return Some(&JsonLimits{MaxBytes: bytes, MaxDepth: depth, MaxValues: values})
}

func TestJsonParseValues(t *testing.T) {
	ctx := RootExecution()
	v := mustOk(t, parseTree(ctx, `{"a":[1,2.50,true,null,"x"],"n":9007199254740993}`, None[*JsonLimits]()))
	obj := v.(JsonValue_ObjectValue).Values
	if obj.Len() != 2 {
		t.Fatalf("entries = %d", obj.Len())
	}
	arr, _ := obj.Lookup("a")
	items := arr.(JsonValue_ArrayValue).Values.Items
	if items[1].(JsonValue_NumberValue).Text != "2.50" || items[2] != (JsonValue_BoolValue{Value: true}) || items[3] != (JsonValue_Null{}) || items[4].(JsonValue_StringValue).Value != "x" {
		t.Fatalf("items = %#v", items)
	}
	n, _ := obj.Lookup("n")
	if n.(JsonValue_NumberValue).Text != "9007199254740993" {
		t.Fatalf("number lost precision: %#v", n)
	}
	out := mustOk(t, stringifyTree(ctx, v, None[int]()))
	if out != `{"a":[1,2.50,true,null,"x"],"n":9007199254740993}` {
		t.Fatalf("stringify = %s", out)
	}
}

func TestJsonParseErrors(t *testing.T) {
	ctx := RootExecution()
	for _, text := range []string{``, `{`, `[1,]`, `{"a":1,"a":2}`, `1 2`, `"\ud800"`, `"\udc00"`, `"\ud800\u0041"`, `{"a" 1}`, `01`, `tru`, `[1}`} {
		mustFail(t, parseTree(ctx, text, None[*JsonLimits]()), JsonError(JsonError_InvalidData{}))
	}
	mustOk(t, parseTree(ctx, `"\ud83d\ude00"`, None[*JsonLimits]()))
}

func TestJsonLimits(t *testing.T) {
	ctx := RootExecution()
	some := func(n int) Option[int] { return Some(n) }
	none := None[int]()
	var limit JsonError = JsonError_LimitExceeded{}
	mustFail(t, parseTree(ctx, `[1]`, jsonLimits(some(2), none, none)), limit)
	mustOk(t, parseTree(ctx, `[1]`, jsonLimits(some(3), none, none)))
	mustFail(t, parseTree(ctx, `[[1]]`, jsonLimits(none, some(1), none)), limit)
	mustOk(t, parseTree(ctx, `[[1]]`, jsonLimits(none, some(2), none)))
	mustOk(t, parseTree(ctx, `1`, jsonLimits(none, some(0), none)))
	mustFail(t, parseTree(ctx, `[]`, jsonLimits(none, some(0), none)), limit)
	mustFail(t, parseTree(ctx, `[1,2]`, jsonLimits(none, none, some(2))), limit)
	mustOk(t, parseTree(ctx, `[1,2]`, jsonLimits(none, none, some(3))))
	for _, l := range []Option[*JsonLimits]{jsonLimits(some(-1), none, none), jsonLimits(none, some(-1), none), jsonLimits(none, none, some(-1))} {
		mustFail(t, parseTree(ctx, `1`, l), JsonError(JsonError_InvalidInput{}))
	}
	// Unset depth stops at the ceiling instead of overflowing the stack.
	deep := strings.Repeat("[", jsonDepthCeiling+1) + strings.Repeat("]", jsonDepthCeiling+1)
	mustFail(t, parseTree(ctx, deep, None[*JsonLimits]()), limit)
}

func TestJsonStringify(t *testing.T) {
	ctx := RootExecution()
	str := func(s string) JsonValue { return JsonValue_StringValue{Value: s} }
	got := mustOk(t, stringifyTree(ctx, str("<a&b>\u2028\"\n"), None[int]()))
	if got != `"\u003ca\u0026b\u003e\u2028\"\n"` {
		t.Fatalf("got %s", got)
	}
	for _, bad := range []string{"", "-", "1.", "01", "+1", "1e", "NaN", " 1", "0x1", ".5"} {
		mustFail(t, stringifyTree(ctx, JsonValue_NumberValue{Text: bad}, None[int]()), JsonError(JsonError_InvalidData{}))
	}
	mustOk(t, stringifyTree(ctx, JsonValue_NumberValue{Text: "-1.5e+10"}, None[int]()))
	mustFail(t, stringifyTree(ctx, str("hello"), Some(int(6))), JsonError(JsonError_LimitExceeded{}))
	mustOk(t, stringifyTree(ctx, str("hello"), Some(int(7))))
	mustFail(t, stringifyTree(ctx, str("x"), Some(int(-1))), JsonError(JsonError_InvalidInput{}))
	// Cyclic values are rejected, shared acyclic values are not.
	list := NewList[JsonValue]()
	list.Items = append(list.Items, JsonValue_ArrayValue{Values: list})
	mustFail(t, stringifyTree(ctx, JsonValue_ArrayValue{Values: list}, None[int]()), JsonError(JsonError_InvalidData{}))
	m := NewMap[string, JsonValue]()
	m.Put("self", JsonValue_ObjectValue{Values: m})
	mustFail(t, stringifyTree(ctx, JsonValue_ObjectValue{Values: m}, None[int]()), JsonError(JsonError_InvalidData{}))
	shared := JsonValue_ArrayValue{Values: NewList[JsonValue](JsonValue_Null{})}
	if got := mustOk(t, stringifyTree(ctx, JsonValue_ArrayValue{Values: NewList[JsonValue](shared, shared)}, None[int]())); got != "[[null],[null]]" {
		t.Fatalf("shared = %s", got)
	}
	if !wasCancelled(func() { stringifyTree(cancelledExec(), JsonValue_Null{}, None[int]()) }) {
		t.Fatal("stringify ignored cancellation")
	}
}

func jsonEqual(a, b JsonValue) bool {
	switch x := a.(type) {
	case JsonValue_ArrayValue:
		y, ok := b.(JsonValue_ArrayValue)
		if !ok || len(x.Values.Items) != len(y.Values.Items) {
			return false
		}
		for i := range x.Values.Items {
			if !jsonEqual(x.Values.Items[i], y.Values.Items[i]) {
				return false
			}
		}
		return true
	case JsonValue_ObjectValue:
		y, ok := b.(JsonValue_ObjectValue)
		if !ok || x.Values.Len() != y.Values.Len() {
			return false
		}
		xs, ys := x.Values.Snapshot(), y.Values.Snapshot()
		for i := range xs {
			if xs[i].Key != ys[i].Key || !jsonEqual(xs[i].Value, ys[i].Value) {
				return false
			}
		}
		return true
	}
	return a == b
}

// FuzzJsonRoundTrip checks that parsing never panics and that any accepted
// document stringifies to text that parses back to an equal value.
func FuzzJsonRoundTrip(f *testing.F) {
	for _, s := range []string{`null`, `[1,2.5,-0,1e3]`, `{"a":{"b":[true,false,null]}}`, `"😀"`, `{"n":9007199254740993}`, `"a\u0000b"`, `[[[[]]]]`} {
		f.Add(s)
	}
	ctx := RootExecution()
	limits := jsonLimits(Some(int(1<<16)), Some(int(32)), Some(int(1<<12)))
	f.Fuzz(func(t *testing.T, text string) {
		parsed := parseTree(ctx, text, limits)
		if parsed.Failed {
			return
		}
		out := stringifyTree(ctx, parsed.Val, Some(int(1<<20)))
		if out.Failed {
			t.Fatalf("parsed value does not stringify: %q -> %#v", text, out.Err)
		}
		again := parseTree(ctx, out.Val, limits)
		if again.Failed || !jsonEqual(parsed.Val, again.Val) {
			t.Fatalf("round trip changed value: %q -> %q", text, out.Val)
		}
	})
}

func csvOpts(delimiter, ending string) *CsvOptions {
	return &CsvOptions{Delimiter: delimiter, LineEnding: ending}
}

func rowsOf(rows ...[]string) *List[*List[string]] {
	out := NewList[*List[string]]()
	for _, r := range rows {
		out.Items = append(out.Items, NewList(r...))
	}
	return out
}

func rowsEqual(a, b *List[*List[string]]) bool {
	if len(a.Items) != len(b.Items) {
		return false
	}
	for i := range a.Items {
		x, y := a.Items[i].Items, b.Items[i].Items
		if len(x) != len(y) {
			return false
		}
		for j := range x {
			if x[j] != y[j] {
				return false
			}
		}
	}
	return true
}

func TestCsvParseAndStringify(t *testing.T) {
	ctx := RootExecution()
	def := csvOpts(",", "\n")
	rows := mustOk(t, Csv_Parse(ctx, "a,b\n\n\"q\"\"x\",\r\nc\r\n", def, None[int](), None[int]()))
	if !rowsEqual(rows, rowsOf([]string{"a", "b"}, []string{`q"x`, ""}, []string{"c"})) {
		t.Fatalf("rows = %v", rows)
	}
	if got := mustOk(t, Csv_Stringify(ctx, rowsOf([]string{"a", "b c", " d", `e"f`}, []string{""}, []string{}), def, None[int]())); got != "a,b c,\" d\",\"e\"\"f\"\n\"\"\n\n" {
		t.Fatalf("stringify = %q", got)
	}
	if got := mustOk(t, Csv_Stringify(ctx, rowsOf([]string{"a", "x\ny"}), csvOpts(";", "\r\n"), None[int]())); got != "a;\"x\r\ny\"\r\n" {
		t.Fatalf("crlf = %q", got)
	}
}

func TestCsvErrorsAndLimits(t *testing.T) {
	ctx := RootExecution()
	none := None[int]()
	for _, o := range []*CsvOptions{csvOpts("", "\n"), csvOpts(",,", "\n"), csvOpts("\"", "\n"), csvOpts("\n", "\n"), csvOpts("\x00", "\n"), csvOpts("é", "\n"), csvOpts(",", "\r"), csvOpts(",", "")} {
		mustFail(t, Csv_Parse(ctx, "a", o, none, none), CsvError(CsvError_InvalidInput{}))
		mustFail(t, Csv_Stringify(ctx, rowsOf(), o, none), CsvError(CsvError_InvalidInput{}))
	}
	mustFail(t, Csv_Parse(ctx, "a", csvOpts(",", "\n"), Some(int(-1)), none), CsvError(CsvError_InvalidInput{}))
	mustFail(t, Csv_Parse(ctx, "a", csvOpts(",", "\n"), none, Some(int(-1))), CsvError(CsvError_InvalidInput{}))
	mustFail(t, Csv_Parse(ctx, "a,\"b", csvOpts(",", "\n"), none, none), CsvError(CsvError_InvalidData{}))
	mustFail(t, Csv_Parse(ctx, "a\nb\n", csvOpts(",", "\n"), Some(int(1)), none), CsvError(CsvError_LimitExceeded{}))
	mustOk(t, Csv_Parse(ctx, "a\nb\n", csvOpts(",", "\n"), Some(int(2)), none))
	mustFail(t, Csv_Parse(ctx, "a,b\nc\n", csvOpts(",", "\n"), none, Some(int(2))), CsvError(CsvError_LimitExceeded{}))
	mustOk(t, Csv_Parse(ctx, "a,b\nc\n", csvOpts(",", "\n"), none, Some(int(3))))
	mustFail(t, Csv_Stringify(ctx, rowsOf([]string{"abc"}), csvOpts(",", "\n"), Some(int(3))), CsvError(CsvError_LimitExceeded{}))
	mustOk(t, Csv_Stringify(ctx, rowsOf([]string{"abc"}), csvOpts(",", "\n"), Some(int(4))))
	mustFail(t, Csv_Stringify(ctx, rowsOf(), csvOpts(",", "\n"), Some(int(-1))), CsvError(CsvError_InvalidInput{}))
}

func TestCsvStringifyKeepsCarriageReturns(t *testing.T) {
	ctx := RootExecution()
	for _, ending := range []string{"\n", "\r\n"} {
		options := csvOpts(",", ending)
		rows := rowsOf([]string{"a\rb", "\r", "x\ny", ""}, []string{""})
		out := mustOk(t, Csv_Stringify(ctx, rows, options, Some(int(1000))))
		back := mustOk(t, Csv_Parse(ctx, out, options, Some(int(10)), Some(int(10))))
		if !rowsEqual(rows, back) {
			t.Fatalf("%q: %q changed rows", ending, out)
		}
	}
}

// FuzzCsvRoundTrip checks that stringified rows parse back unchanged.
func FuzzCsvRoundTrip(f *testing.F) {
	for _, s := range []string{"a,b\nc,d", "x\n\ny", "\"q\"\"uote\",\n", "line\r\nbreak,\rcarriage", ",,,", ""} {
		f.Add(s, byte(','), false)
	}
	ctx := RootExecution()
	f.Fuzz(func(t *testing.T, text string, delimiter byte, crlf bool) {
		if !utf8.ValidString(text) || strings.Contains(text, "\r\n") || delimiter >= 128 || strings.IndexByte("\"\r\n\x00", delimiter) >= 0 {
			t.Skip()
		}
		ending := "\n"
		if crlf {
			ending = "\r\n"
		}
		options := csvOpts(string([]byte{delimiter}), ending)
		var lines [][]string
		for _, line := range strings.Split(text, "\n") {
			lines = append(lines, strings.Split(line, string([]byte{delimiter})))
		}
		rows := rowsOf(lines...)
		out := Csv_Stringify(ctx, rows, options, Some(int(1<<20)))
		if out.Failed {
			t.Fatalf("stringify failed: %#v", out.Err)
		}
		back := Csv_Parse(ctx, out.Val, options, Some(int(1<<20)), Some(int(1<<20)))
		if back.Failed || !rowsEqual(rows, back.Val) {
			t.Fatalf("round trip changed rows: %q -> %q", text, out.Val)
		}
	})
}

func TestCompressRoundTripAndErrors(t *testing.T) {
	ctx := RootExecution()
	data := NewBytes([]byte(strings.Repeat("hello manuscript ", 200)))
	for _, f := range []string{"gzip", "zlib", "deflate"} {
		for _, level := range []int{0, 1, 6, 9} {
			enc := mustOk(t, Compress_Compress(ctx, data, f, level, None[int]()))
			dec := mustOk(t, Compress_Decompress(ctx, enc, f, Some(int(len(data.Data)))))
			if string(dec.Data) != string(data.Data) {
				t.Fatalf("%s level %d round trip", f, level)
			}
			mustFail(t, Compress_Decompress(ctx, enc, f, Some(int(len(data.Data)-1))), CompressionError(CompressionError_LimitExceeded{}))
		}
	}
	for _, level := range []int{-1, 10} {
		mustFail(t, Compress_Compress(ctx, data, "gzip", level, None[int]()), CompressionError(CompressionError_InvalidInput{}))
	}
	mustFail(t, Compress_Compress(ctx, data, "gzip", 6, Some(int(-1))), CompressionError(CompressionError_InvalidInput{}))
	mustFail(t, Compress_Decompress(ctx, data, "gzip", Some(int(-1))), CompressionError(CompressionError_InvalidInput{}))
	mustFail(t, Compress_Compress(ctx, data, "GZIP", 6, None[int]()), CompressionError(CompressionError_Unsupported{}))
	mustFail(t, Compress_Decompress(ctx, data, "br", None[int]()), CompressionError(CompressionError_Unsupported{}))
	mustFail(t, Compress_Compress(ctx, data, "gzip", 6, Some(int(10))), CompressionError(CompressionError_LimitExceeded{}))
	mustFail(t, Compress_Decompress(ctx, data, "gzip", None[int]()), CompressionError(CompressionError_InvalidData{}))
	enc := mustOk(t, Compress_Compress(ctx, data, "zlib", 6, None[int]()))
	mustFail(t, Compress_Decompress(ctx, NewBytes(append(append([]byte{}, enc.Data...), 0)), "zlib", None[int]()), CompressionError(CompressionError_InvalidData{}))
	// Concatenated gzip members share one cumulative limit.
	one := mustOk(t, Compress_Compress(ctx, NewBytes([]byte("abcd")), "gzip", 6, None[int]()))
	two := NewBytes(append(append([]byte{}, one.Data...), one.Data...))
	if got := mustOk(t, Compress_Decompress(ctx, two, "gzip", Some(int(8)))); string(got.Data) != "abcdabcd" {
		t.Fatalf("members = %q", got.Data)
	}
	mustFail(t, Compress_Decompress(ctx, two, "gzip", Some(int(7))), CompressionError(CompressionError_LimitExceeded{}))
}

func TestCompressionFormatSelectors(t *testing.T) {
	ctx := RootExecution()
	in := NewBytes([]byte("hello"))
	for _, f := range []CompressionFormat{CompressionFormat_Gzip{}, CompressionFormat_Zlib{}, CompressionFormat_Deflate{}} {
		enc := mustOk(t, CompressionFormat_Compress(ctx, f, in, 6, None[int]()))
		dec := mustOk(t, CompressionFormat_Decompress(ctx, f, enc, Some(int(5))))
		if string(dec.Data) != "hello" {
			t.Fatalf("%T", f)
		}
	}
	// Gzip output has a zero timestamp and no name metadata.
	enc := mustOk(t, Compress_Compress(ctx, in, "gzip", 6, None[int]()))
	if hex.EncodeToString(enc.Data[:8]) != "1f8b080000000000" {
		t.Fatalf("header = %x", enc.Data[:10])
	}
	if !wasCancelled(func() { CompressionFormat_Compress(cancelledExec(), CompressionFormat_Gzip{}, in, 6, None[int]()) }) {
		t.Fatal("selector ignored cancellation")
	}
}

func TestArchiveRoundTrip(t *testing.T) {
	ctx := RootExecution()
	entries := NewList(
		&ArchiveEntry{Path: "dir", Data: NewBytes(nil), Directory: true},
		&ArchiveEntry{Path: "dir/a.txt", Data: NewBytes([]byte("alpha")), Directory: false},
		&ArchiveEntry{Path: "empty", Data: NewBytes([]byte{}), Directory: false},
	)
	for _, format := range []ArchiveFormat{ArchiveFormat_Zip{}, ArchiveFormat_Tar{}} {
		packed := mustOk(t, ArchiveFormat_Pack(ctx, format, entries, None[int]()))
		again := mustOk(t, ArchiveFormat_Pack(ctx, format, entries, None[int]()))
		if string(packed.Data) != string(again.Data) {
			t.Fatalf("%T pack is not deterministic", format)
		}
		out := mustOk(t, ArchiveFormat_Unpack(ctx, format, packed, None[*ArchiveLimits]()))
		if len(out.Items) != 3 {
			t.Fatalf("%T entries = %d", format, len(out.Items))
		}
		for i, want := range entries.Items {
			got := out.Items[i]
			if got.Path != want.Path || got.Directory != want.Directory || string(got.Data.Data) != string(want.Data.Data) {
				t.Fatalf("%T entry %d = %#v", format, i, got)
			}
		}
	}
	// A trailing slash on a directory is accepted and dropped.
	slash := NewList(&ArchiveEntry{Path: "d/", Data: NewBytes(nil), Directory: true})
	packed := mustOk(t, Archive_Pack(ctx, slash, "tar", None[int]()))
	if got := mustOk(t, Archive_Unpack(ctx, packed, "tar", None[*ArchiveLimits]())); got.Items[0].Path != "d" {
		t.Fatalf("path = %q", got.Items[0].Path)
	}
}

func TestArchivePackValidation(t *testing.T) {
	ctx := RootExecution()
	file := func(p string) *ArchiveEntry { return &ArchiveEntry{Path: p, Data: NewBytes([]byte("x"))} }
	pack := func(format string, e ...*ArchiveEntry) Result[*Bytes, ArchiveError] {
		return Archive_Pack(ctx, NewList(e...), format, None[int]())
	}
	var invalidInput ArchiveError = ArchiveError_InvalidInput{}
	for _, p := range []string{"", "/abs", "a/../b", "..", ".", "a//b", "a\\b", "c:x", "a\x00", "dir/", "\xff"} {
		mustFail(t, pack("zip", file(p)), invalidInput)
	}
	mustFail(t, pack("tar", &ArchiveEntry{Path: "d", Data: NewBytes([]byte("x")), Directory: true}), invalidInput)
	mustFail(t, pack("zip", file("a"), file("a")), ArchiveError(ArchiveError_InvalidData{}))
	mustFail(t, pack("zip", file("a"), file("a/b")), ArchiveError(ArchiveError_InvalidData{}))
	mustFail(t, pack("rar", file("a")), ArchiveError(ArchiveError_Unsupported{}))
	mustFail(t, pack("ZIP", file("a")), ArchiveError(ArchiveError_Unsupported{}))
	long := file(strings.Repeat("a", 1<<16))
	mustFail(t, pack("zip", long), invalidInput)
	mustOk(t, pack("tar", long))
	mustFail(t, Archive_Pack(ctx, NewList(file("a")), "tar", Some(int(-1))), invalidInput)
	mustFail(t, Archive_Pack(ctx, NewList(file("a")), "tar", Some(int(100))), ArchiveError(ArchiveError_LimitExceeded{}))
}

func TestArchiveUnpackLimitsAndMalformed(t *testing.T) {
	ctx := RootExecution()
	entries := NewList(
		&ArchiveEntry{Path: "a", Data: NewBytes([]byte("12345"))},
		&ArchiveEntry{Path: "b", Data: NewBytes([]byte("678"))},
	)
	limits := func(n, e, tot Option[int]) Option[*ArchiveLimits] {
		return Some(&ArchiveLimits{MaxEntries: n, MaxEntryBytes: e, MaxTotalBytes: tot})
	}
	none := None[int]()
	var limit ArchiveError = ArchiveError_LimitExceeded{}
	for _, format := range []string{"zip", "tar"} {
		packed := mustOk(t, Archive_Pack(ctx, entries, format, None[int]()))
		mustFail(t, Archive_Unpack(ctx, packed, format, limits(Some(int(1)), none, none)), limit)
		mustOk(t, Archive_Unpack(ctx, packed, format, limits(Some(int(2)), none, none)))
		mustFail(t, Archive_Unpack(ctx, packed, format, limits(none, Some(int(4)), none)), limit)
		mustOk(t, Archive_Unpack(ctx, packed, format, limits(none, Some(int(5)), none)))
		mustFail(t, Archive_Unpack(ctx, packed, format, limits(none, none, Some(int(7)))), limit)
		mustOk(t, Archive_Unpack(ctx, packed, format, limits(none, none, Some(int(8)))))
		mustFail(t, Archive_Unpack(ctx, packed, format, limits(Some(int(-1)), none, none)), ArchiveError(ArchiveError_InvalidInput{}))
		mustFail(t, Archive_Unpack(ctx, NewBytes([]byte("garbage that is not an archive")), format, None[*ArchiveLimits]()), ArchiveError(ArchiveError_InvalidData{}))
	}
	mustFail(t, Archive_Unpack(ctx, NewBytes(nil), "7z", None[*ArchiveLimits]()), ArchiveError(ArchiveError_Unsupported{}))
	if !wasCancelled(func() { Archive_Pack(cancelledExec(), entries, "zip", None[int]()) }) {
		t.Fatal("pack ignored cancellation")
	}
}

func hexOf(b *Bytes) string { return hex.EncodeToString(b.Data) }

func TestCryptoHashes(t *testing.T) {
	ctx := RootExecution()
	abc := NewBytes([]byte("abc"))
	if got := hexOf(Crypto_Sha256(ctx, abc)); got != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" {
		t.Fatalf("sha256 = %s", got)
	}
	if got := hexOf(Crypto_Sha384(ctx, abc)); got != "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7" {
		t.Fatalf("sha384 = %s", got)
	}
	if got := hexOf(Crypto_Sha512(ctx, abc)); !strings.HasPrefix(got, "ddaf35a193617aba") {
		t.Fatalf("sha512 = %s", got)
	}
	for _, a := range []HashAlgorithm{HashAlgorithm_Sha256{}, HashAlgorithm_Sha384{}, HashAlgorithm_Sha512{}} {
		var want *Bytes
		switch a.(type) {
		case HashAlgorithm_Sha256:
			want = Crypto_Sha256(ctx, abc)
		case HashAlgorithm_Sha384:
			want = Crypto_Sha384(ctx, abc)
		default:
			want = Crypto_Sha512(ctx, abc)
		}
		if hexOf(HashAlgorithm_Digest(ctx, a, abc)) != hexOf(want) {
			t.Fatalf("%T digest", a)
		}
	}
	// RFC 4231 test case 2.
	key, data := NewBytes([]byte("Jefe")), NewBytes([]byte("what do ya want for nothing?"))
	want := "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
	if got := hexOf(mustOk(t, Crypto_Hmac(ctx, key, data, "sha256"))); got != want {
		t.Fatalf("hmac = %s", got)
	}
	if got := hexOf(mustOk(t, HashAlgorithm_Hmac(ctx, HashAlgorithm_Sha256{}, key, data))); got != want {
		t.Fatalf("typed hmac = %s", got)
	}
	mustFail(t, Crypto_Hmac(ctx, key, data, "md5"), CryptoError(CryptoError_Unsupported{}))
	mustFail(t, Crypto_Hmac(ctx, key, data, "SHA256"), CryptoError(CryptoError_Unsupported{}))
	if !Crypto_ConstantTimeEqual(ctx, abc, NewBytes([]byte("abc"))) || Crypto_ConstantTimeEqual(ctx, abc, NewBytes([]byte("abd"))) || Crypto_ConstantTimeEqual(ctx, abc, NewBytes([]byte("ab"))) {
		t.Fatal("constant time equal")
	}
}

func TestCryptoDeriveKey(t *testing.T) {
	ctx := RootExecution()
	// RFC 7914 PBKDF2-HMAC-SHA256 vector: password, salt, c=1, dkLen=32.
	got := mustOk(t, Crypto_DeriveKey(ctx, NewBytes([]byte("passwd")), NewBytes([]byte("salt")), 1, 32))
	if hexOf(got) != "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc" {
		t.Fatalf("pbkdf2 = %s", hexOf(got))
	}
	long := mustOk(t, Crypto_DeriveKey(ctx, NewBytes([]byte("p")), NewBytes([]byte("s")), 3, 50))
	if len(long.Data) != 50 {
		t.Fatalf("len = %d", len(long.Data))
	}
	for _, c := range [][2]int{{0, 32}, {1, 0}, {1, -1}, {1, 1048577}} {
		mustFail(t, Crypto_DeriveKey(ctx, NewBytes(nil), NewBytes(nil), c[0], c[1]), CryptoError(CryptoError_InvalidInput{}))
	}
}

func TestCryptoSealOpenSign(t *testing.T) {
	ctx := RootExecution()
	key := NewBytes([]byte(strings.Repeat("k", 32)))
	nonce := NewBytes([]byte(strings.Repeat("n", 12)))
	aad := NewBytes([]byte("aad"))
	sealed := mustOk(t, Crypto_Seal(ctx, key, nonce, NewBytes([]byte("secret")), aad))
	if opened := mustOk(t, Crypto_Open(ctx, key, nonce, sealed, aad)); string(opened.Data) != "secret" {
		t.Fatalf("opened = %q", opened.Data)
	}
	mustFail(t, Crypto_Open(ctx, key, nonce, sealed, NewBytes([]byte("other"))), CryptoError(CryptoError_AuthenticationFailed{}))
	mustFail(t, Crypto_Open(ctx, NewBytes([]byte("short")), nonce, sealed, aad), CryptoError(CryptoError_InvalidInput{}))
	mustFail(t, Crypto_Seal(ctx, key, NewBytes([]byte("n")), sealed, aad), CryptoError(CryptoError_InvalidInput{}))

	seed := NewBytes([]byte(strings.Repeat("s", 32)))
	pub := mustOk(t, Crypto_PublicKey(ctx, seed))
	sig := mustOk(t, Crypto_Sign(ctx, seed, NewBytes([]byte("msg"))))
	if !Crypto_Verify(ctx, pub, NewBytes([]byte("msg")), sig) || Crypto_Verify(ctx, pub, NewBytes([]byte("other")), sig) || Crypto_Verify(ctx, NewBytes([]byte("short")), NewBytes([]byte("msg")), sig) {
		t.Fatal("ed25519 verify")
	}
	mustFail(t, Crypto_Sign(ctx, NewBytes([]byte("x")), NewBytes(nil)), CryptoError(CryptoError_InvalidInput{}))
	mustFail(t, Crypto_PublicKey(ctx, NewBytes([]byte("x"))), CryptoError(CryptoError_InvalidInput{}))
	if !wasCancelled(func() { Crypto_Sha256(cancelledExec(), NewBytes([]byte("x"))) }) {
		t.Fatal("digest ignored cancellation")
	}
}

// fixedEntropy is a deterministic Entropy that serves a scripted byte stream.
type fixedEntropy struct {
	stream []byte
	short  bool
	err    RandomError
	asked  []int
}

func (e *fixedEntropy) Bytes(_ *Execution, count int) Result[*Bytes, RandomError] {
	e.asked = append(e.asked, count)
	if e.err != nil {
		return Fail[*Bytes, RandomError](e.err)
	}
	n := int(count)
	if e.short {
		n--
	}
	out := make([]byte, n)
	for i := range out {
		out[i] = e.stream[0]
		e.stream = append(e.stream[1:], e.stream[0])
	}
	return Ok[*Bytes, RandomError](NewBytes(out))
}

func TestRandomUuidV4(t *testing.T) {
	ctx := RootExecution()
	e := &fixedEntropy{stream: []byte{0xff}}
	if got := mustOk(t, Random_UuidV4(ctx, e)); got != "ffffffff-ffff-4fff-bfff-ffffffffffff" {
		t.Fatalf("uuid = %s", got)
	}
	e = &fixedEntropy{stream: []byte{0}}
	if got := mustOk(t, Random_UuidV4(ctx, e)); got != "00000000-0000-4000-8000-000000000000" {
		t.Fatalf("uuid = %s", got)
	}
	mustFail(t, Random_UuidV4(ctx, &fixedEntropy{stream: []byte{1}, short: true}), RandomError(RandomError_Failed{Message: "entropy source returned incorrect length"}))
	mustFail(t, Random_UuidV4(ctx, &fixedEntropy{err: RandomError_Failed{Message: "boom"}}), RandomError(RandomError_Failed{Message: "boom"}))
	// The operating system source yields distinct, well-formed ids.
	a := mustOk(t, Random_UuidV4(ctx, Random_Entropy(ctx)))
	b := mustOk(t, Random_UuidV4(ctx, Random_Entropy(ctx)))
	if a == b || len(a) != 36 || a[14] != '4' {
		t.Fatalf("uuids = %s %s", a, b)
	}
}

func TestRandomSecureInt(t *testing.T) {
	ctx := RootExecution()
	// Width 10 needs 4 bits; the first draw 0x1f&0x0f=15 is rejected, then 7.
	e := &fixedEntropy{stream: []byte{0x1f, 0x07}}
	if got := mustOk(t, Random_SecureInt(ctx, e, 100, Some(int(110)))); got != 107 {
		t.Fatalf("got %d", got)
	}
	if len(e.asked) != 2 || e.asked[0] != 1 {
		t.Fatalf("asked = %v", e.asked)
	}
	mustFail(t, Random_SecureInt(ctx, e, 5, Some(int(5))), RandomError(RandomError_InvalidInput{}))
	mustFail(t, Random_SecureInt(ctx, e, 6, Some(int(5))), RandomError(RandomError_InvalidInput{}))
	mustFail(t, Random_SecureInt(ctx, &fixedEntropy{stream: []byte{1}, short: true}, 0, Some(int(10))), RandomError(RandomError_Failed{Message: "entropy source returned incorrect length"}))
	mustFail(t, Random_SecureInt(ctx, &fixedEntropy{err: RandomError_LimitExceeded{}}, 0, Some(int(10))), RandomError(RandomError_LimitExceeded{}))
	// Full range and wide spans need eight bytes and stay in range.
	for i := 0; i < 200; i++ {
		v := mustOk(t, Random_SecureInt(ctx, Random_Entropy(ctx), math.MinInt64, None[int]()))
		_ = v
		w := mustOk(t, Random_SecureInt(ctx, Random_Entropy(ctx), -3, Some(int(4))))
		if w < -3 || w >= 4 {
			t.Fatalf("out of range: %d", w)
		}
	}
	if !wasCancelled(func() { Random_SecureInt(cancelledExec(), e, 0, Some(int(10))) }) {
		t.Fatal("secure_int ignored cancellation")
	}
}

func TestOsEntropy(t *testing.T) {
	ctx := RootExecution()
	e := Random_Entropy(ctx)
	if b := mustOk(t, e.Bytes(ctx, 0)); len(b.Data) != 0 {
		t.Fatal("zero bytes")
	}
	if b := mustOk(t, e.Bytes(ctx, 70000)); len(b.Data) != 70000 {
		t.Fatal("70000 bytes")
	}
	mustFail(t, e.Bytes(ctx, -1), RandomError(RandomError_InvalidInput{}))
	mustFail(t, e.Bytes(ctx, 16*1024*1024+1), RandomError(RandomError_InvalidInput{}))
	if !wasCancelled(func() { e.Bytes(cancelledExec(), 10) }) {
		t.Fatal("entropy ignored cancellation")
	}
}

func TestPathPosix(t *testing.T) {
	ctx := RootExecution()
	p := Path_Posix(ctx)
	check := func(name, got, want string) {
		t.Helper()
		if got != want {
			t.Errorf("%s = %q, want %q", name, got, want)
		}
	}
	check("normalize", p.Normalize(ctx, "/a/./b//c/../d/"), "/a/b/d/")
	check("normalize empty", p.Normalize(ctx, ""), ".")
	check("normalize ..", p.Normalize(ctx, "../../a"), "../../a")
	check("normalize root ..", p.Normalize(ctx, "/../a"), "/a")
	check("basename", p.Basename(ctx, "/a/b.txt/"), "b.txt")
	check("basename_without", p.BasenameWithout(ctx, "/a/b.txt", ".txt"), "b")
	check("basename_without same", p.BasenameWithout(ctx, "x.txt", "x.txt"), "")
	check("dirname", p.Dirname(ctx, "/a/b/c"), "/a/b")
	check("dirname root", p.Dirname(ctx, "/a"), "/")
	check("dirname bare", p.Dirname(ctx, "a"), ".")
	check("extension", p.Extension(ctx, "a/b.tar.gz"), ".gz")
	check("extension dotfile", p.Extension(ctx, ".bashrc"), "")
	check("join", p.Join(ctx, NewList("a", "", "b/", "../c")), "a/c")
	check("separator", p.Separator(ctx), "/")
	check("delimiter", p.Delimiter(ctx), ":")
	check("namespaced", p.ToNamespacedPath(ctx, "/a"), "/a")
	if !p.IsAbsolute(ctx, "/a") || p.IsAbsolute(ctx, "a") {
		t.Error("is_absolute")
	}
	parts := p.Parse(ctx, "/home/u/file.txt")
	if *parts != (PathParts{Root: "/", Directory: "/home/u", Base: "file.txt", Extension: ".txt", Name: "file"}) {
		t.Errorf("parse = %#v", *parts)
	}
	check("format", p.Format(ctx, parts), "/home/u/file.txt")
	check("format name", p.Format(ctx, &PathParts{Directory: "d", Name: "n", Extension: "e"}), "d/n.e")
	check("format root", p.Format(ctx, &PathParts{Root: "/", Directory: "/", Base: "x"}), "/x")
	check("resolve", mustOk(t, p.Resolve(ctx, "/a/b", NewList("../c", "d"))), "/a/c/d")
	check("resolve abs part", mustOk(t, p.Resolve(ctx, "/a", NewList("/x", "y"))), "/x/y")
	check("relative", mustOk(t, p.Relative(ctx, "/a/b", "/a/c/d")), "../c/d")
	mustFail(t, p.Resolve(ctx, "rel", nil2()), PathError(PathError_InvalidInput{}))
	mustFail(t, p.Resolve(ctx, "/a\x00", nil2()), PathError(PathError_InvalidInput{}))
	mustFail(t, p.Relative(ctx, "a", "/b"), PathError(PathError_InvalidInput{}))
}

func nil2() *List[string] { return NewList[string]() }

func TestPathWin32(t *testing.T) {
	ctx := RootExecution()
	p := Path_Win32(ctx)
	if got := p.Normalize(ctx, `C:\a\.\b\..\c`); got != `C:\a\c` {
		t.Errorf("normalize = %q", got)
	}
	if got := p.Basename(ctx, `C:\dir\file.txt`); got != "file.txt" {
		t.Errorf("basename = %q", got)
	}
	if got := p.Dirname(ctx, `C:\dir\file.txt`); got != `C:\dir` {
		t.Errorf("dirname = %q", got)
	}
	if !p.IsAbsolute(ctx, `C:\x`) || p.IsAbsolute(ctx, `C:x`) || !p.IsAbsolute(ctx, `\\server\share\x`) {
		t.Error("is_absolute")
	}
	if p.Separator(ctx) != `\` || p.Delimiter(ctx) != ";" {
		t.Error("separators")
	}
	if got := p.ToNamespacedPath(ctx, `C:\a\b`); got != `\\?\C:\a\b` {
		t.Errorf("namespaced = %q", got)
	}
	if got := p.ToNamespacedPath(ctx, `\\srv\share\f`); got != `\\?\UNC\srv\share\f` {
		t.Errorf("unc = %q", got)
	}
	if got := mustOk(t, p.Relative(ctx, `C:\a\b`, `C:\A\c`)); got != `..\c` {
		t.Errorf("relative = %q", got)
	}
	if got := mustOk(t, p.Relative(ctx, `C:\a`, `D:\b`)); got != `D:\b` {
		t.Errorf("relative drives = %q", got)
	}
	if got := mustOk(t, p.Resolve(ctx, `C:\a`, NewList(`..\b`))); got != `C:\b` {
		t.Errorf("resolve = %q", got)
	}
}

func TestPathMatchesGlob(t *testing.T) {
	ctx := RootExecution()
	p := Path_Posix(ctx)
	for _, c := range []struct {
		path, glob string
		want       bool
	}{
		{"a/b.go", "**/*.go", true},
		{"a/b/c.go", "a/**/c.go", true},
		{"a/.hidden/c.go", "a/**/c.go", false},
		{".x", "*", false},
		{".x", ".*", true},
		{"a.txt", "*.{txt,md}", true},
		{"a.png", "*.{txt,md}", false},
		{"f3", "f{1..5}", true},
		{"f9", "f{1..5}", false},
		{"ab", "@(a|b)b", true},
		{"cb", "!(a|b)b", true},
		{"ab", "[!x]b", true},
	} {
		if got := mustOk(t, p.MatchesGlob(ctx, c.path, c.glob)); got != c.want {
			t.Errorf("matches_glob(%q, %q) = %v", c.path, c.glob, got)
		}
	}
	for _, bad := range []string{"[a", "a\\", "{a,b", "@(a", "a\x00", strings.Repeat("a", 4097), "{1..100000}"} {
		mustFail(t, p.MatchesGlob(ctx, "a", bad), PathError(PathError_InvalidInput{}))
	}
	if Path_Separator(ctx) == "" || Path_Normalize(ctx, "a/../b") != "b" {
		t.Error("host path functions")
	}
}

// A run of stars over a long segment must stay linear in the segment length.
func TestGlobStarRunsAreNotQuadratic(t *testing.T) {
	value := strings.Repeat("a", 4000)
	start := time.Now()
	if pathGlobMatch(value, strings.Repeat("*a", 400)+"b") {
		t.Fatal("pattern ending in b matched a value of only a")
	}
	if !pathGlobMatch(value, strings.Repeat("*a", 400)) {
		t.Fatal("stars and literals failed to match")
	}
	if elapsed := time.Since(start); elapsed > 20*time.Second {
		t.Fatalf("matching took %s", elapsed)
	}
}

func TestGlobStarMatching(t *testing.T) {
	for _, tt := range []struct {
		value, pattern string
		want           bool
	}{
		{"abc", "*", true}, {"", "*", true}, {"abc", "a*c", true}, {"ac", "a*c", true},
		{"abc", "a*b*c", true}, {"abc", "*b*", true}, {"abc", "**c", true}, {"abc", "a?*", true},
		{"a", "a?*", false}, {"abc", "*d", false}, {"abcabc", "*abc*abc", true},
		{"abab", "*ab*ba", false}, {"é", "?*", true},
	} {
		if got := pathGlobMatch(tt.value, tt.pattern); got != tt.want {
			t.Errorf("match(%q, %q) = %v, want %v", tt.value, tt.pattern, got, tt.want)
		}
	}
}

func htmlLimits(bytes, depth, nodes Option[int]) Option[*HtmlLimits] {
	return Some(&HtmlLimits{MaxBytes: bytes, MaxDepth: depth, MaxNodes: nodes})
}

func TestHtmlParseLimitsAndInvalidUTF8(t *testing.T) {
	ctx := RootExecution()
	none := None[int]()
	i := func(n int) Option[int] { return Some(n) }
	// An empty document has Document, html, head and body nodes; head and
	// body have depth two.
	for _, test := range []struct {
		text   string
		limits Option[*HtmlLimits]
		want   HtmlError
	}{
		{"", htmlLimits(i(0), i(2), i(4)), nil},
		{"", htmlLimits(none, none, i(3)), HtmlError_LimitExceeded{}},
		{"", htmlLimits(none, none, i(0)), HtmlError_LimitExceeded{}},
		{"", htmlLimits(none, i(1), none), HtmlError_LimitExceeded{}},
		{"", htmlLimits(none, i(0), none), HtmlError_LimitExceeded{}},
		{"é", htmlLimits(i(1), none, none), HtmlError_LimitExceeded{}},
		{"é", htmlLimits(i(2), none, none), nil},
		{"\xff", None[*HtmlLimits](), HtmlError_InvalidData{}},
		{"", htmlLimits(i(-1), none, none), HtmlError_InvalidInput{}},
		{"", htmlLimits(none, i(-1), none), HtmlError_InvalidInput{}},
		{"", htmlLimits(none, none, i(-1)), HtmlError_InvalidInput{}},
	} {
		r := Html_Parse(ctx, test.text, test.limits)
		if test.want == nil {
			mustOk(t, r)
		} else {
			mustFail(t, r, test.want)
		}
	}
}

func htmlText(n HtmlNode) string {
	switch n := n.(type) {
	case HtmlNode_Text:
		return n.Text
	case HtmlNode_Document:
		var b strings.Builder
		for _, c := range n.Children.Items {
			b.WriteString(htmlText(c))
		}
		return b.String()
	case HtmlNode_Element:
		var b strings.Builder
		for _, c := range n.Children.Items {
			b.WriteString(htmlText(c))
		}
		return b.String()
	}
	return ""
}

func TestHtmlParseTree(t *testing.T) {
	ctx := RootExecution()
	doc := mustOk(t, Html_Parse(ctx, `<!DOCTYPE html><!-- c --><p class="x" data-a=1>Hello <b>world</b> &amp; friends</p><svg viewBox="0 0 1 1"><circle/></svg>`, None[*HtmlLimits]()))
	if got := htmlText(doc); got != "Hello world & friends" {
		t.Fatalf("text = %q", got)
	}
	children := doc.(HtmlNode_Document).Children.Items
	if dt, ok := children[0].(HtmlNode_Doctype); !ok || dt.Name != "html" || dt.PublicId != "" || dt.SystemId != "" {
		t.Fatalf("doctype = %#v", children[0])
	}
	if c, ok := children[1].(HtmlNode_Comment); !ok || c.Text != " c " {
		t.Fatalf("comment = %#v", children[1])
	}
	html := children[2].(HtmlNode_Element)
	if html.Tag != "html" || html.Namespace != "" {
		t.Fatalf("html = %#v", html)
	}
	body := html.Children.Items[1].(HtmlNode_Element)
	p := body.Children.Items[0].(HtmlNode_Element)
	if len(p.Attributes.Items) != 2 || *p.Attributes.Items[0] != (HtmlAttribute{Name: "class", Value: "x"}) || p.Attributes.Items[1].Value != "1" {
		t.Fatalf("attributes = %#v", p.Attributes.Items)
	}
	svg := body.Children.Items[1].(HtmlNode_Element)
	if svg.Tag != "svg" || svg.Namespace != "svg" {
		t.Fatalf("svg = %#v", svg)
	}
}

func TestHtmlParseLargeAndDeepDocuments(t *testing.T) {
	ctx := RootExecution()
	for _, text := range []string{
		strings.Repeat("<p>é &amp; 🙂</p>", 1000),
		strings.Repeat("<div>", 600) + "deep" + strings.Repeat("</div>", 600),
	} {
		mustOk(t, Html_Parse(ctx, text, None[*HtmlLimits]()))
	}
}

func TestHtmlEscapeUnescape(t *testing.T) {
	ctx := RootExecution()
	if got := Html_Escape(ctx, `<a href="x">&'</a>`); got != "&lt;a href=&#34;x&#34;&gt;&amp;&#39;&lt;/a&gt;" {
		t.Fatalf("escape = %q", got)
	}
	for in, want := range map[string]string{"&lt;&gt;&amp;": "<>&", "&#225;&#xE1;": "áá", "&ampx": "&x", "&bogus;": "&bogus;", "&amp;lt;": "&lt;", "&#0;": "\ufffd", "&#128;": "\u20ac"} {
		if got := Html_Unescape(ctx, in); got != want {
			t.Errorf("unescape(%q) = %q, want %q", in, got, want)
		}
	}
	if !wasCancelled(func() { Html_Unescape(cancelledExec(), "") }) {
		t.Fatal("unescape ignored entry cancellation")
	}
	if !wasCancelled(func() { Html_Parse(cancelledExec(), strings.Repeat("x", 10000), None[*HtmlLimits]()) }) {
		t.Fatal("parse ignored cancellation")
	}
	for _, s := range []string{"", "a b&c=d", "é🙂%/?#", "&amp;<>\"'"} {
		if got := Html_Unescape(ctx, Html_Escape(ctx, s)); got != s {
			t.Errorf("round trip %q -> %q", s, got)
		}
	}
}

// FuzzHtmlEscapeRoundTrip checks that unescape inverts escape.
func FuzzHtmlEscapeRoundTrip(f *testing.F) {
	for _, s := range []string{"", "a b&c=d", "é🙂%/?#", "&amp;<>\"'"} {
		f.Add(s)
	}
	ctx := RootExecution()
	f.Fuzz(func(t *testing.T, text string) {
		if !utf8.ValidString(text) {
			return
		}
		if got := Html_Unescape(ctx, Html_Escape(ctx, text)); got != text {
			t.Fatalf("round trip: %q -> %q", text, got)
		}
	})
}

func TestDataErrorMessages(t *testing.T) {
	ctx := RootExecution()
	for got, want := range map[string]string{
		Errors_Message_JsonError(ctx, JsonError_InvalidInput{}):                            "JSON: invalid input",
		Errors_Message_JsonError(ctx, JsonError_InvalidData{}):                             "JSON: invalid data",
		Errors_Message_JsonError(ctx, JsonError_LimitExceeded{}):                           "JSON: limit exceeded",
		Errors_Message_CsvError(ctx, CsvError_InvalidData{}):                               "CSV: invalid data",
		Errors_Message_HtmlError(ctx, HtmlError_LimitExceeded{}):                           "HTML: limit exceeded",
		Errors_Message_PathError(ctx, PathError_InvalidInput{}):                            "path: invalid input",
		Errors_Message_CryptoError(ctx, CryptoError_Unsupported{}):                         "cryptography: operation not supported",
		Errors_Message_CryptoError(ctx, CryptoError_AuthenticationFailed{}):                "cryptography: authentication failed",
		Errors_Message_CompressionError(ctx, CompressionError_Unsupported{}):               "compression: operation not supported",
		Errors_Message_CompressionError(ctx, CompressionError_Failed{Message: "verbatim"}): "verbatim",
		Errors_Message_ArchiveError(ctx, ArchiveError_InvalidInput{}):                      "archive: invalid input",
		Errors_Message_ArchiveError(ctx, ArchiveError_Failed{Message: "as is"}):            "as is",
		Errors_Message_RandomError(ctx, RandomError_LimitExceeded{}):                       "random: limit exceeded",
		Errors_Message_RandomError(ctx, RandomError_Failed{Message: "no entropy"}):         "no entropy",
	} {
		if got != want {
			t.Errorf("message = %q, want %q", got, want)
		}
	}
}

// stringifyTree serializes an already-built JsonValue compactly.
func stringifyTree(ctx *Execution, v JsonValue, max Option[int]) Result[string, JsonError] {
	return Json_Stringify(ctx, JsonEncValue, v, max, None[int]())
}

// parseTree parses text into an untyped JsonValue.
func parseTree(ctx *Execution, text string, limits Option[*JsonLimits]) Result[JsonValue, JsonError] {
	return Json_Parse(ctx, JsonDecValue, text, limits, true)
}
