package msruntime

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func fuzzJSONLimits() Record {
	return Record{"@std/JsonLimits", map[string]Value{"max_bytes": int64(1 << 16), "max_depth": int64(32), "max_values": int64(1 << 12)}}
}

// FuzzJSONRoundTrip checks that parsing never panics and that any accepted
// document stringifies to text that parses back to an equal value.
func FuzzJSONRoundTrip(f *testing.F) {
	for _, s := range []string{`null`, `[1,2.5,-0,1e3]`, `{"a":{"b":[true,false,null]}}`, `"😀"`, `{"n":9007199254740993}`, `"a\u0000b"`, `[[[[]]]]`} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		parsed := libraryCall(t, "json/parse", text, fuzzJSONLimits())
		if parsed.Tag != "ok" {
			return
		}
		value := parsed.Fields[0]
		out := libraryCall(t, "json/stringify", value, int64(1<<20))
		if out.Tag != "ok" {
			t.Fatalf("parsed value does not stringify: %q -> %#v", text, out)
		}
		again := libraryCall(t, "json/parse", out.Fields[0], fuzzJSONLimits())
		if again.Tag != "ok" || !Equal(value, again.Fields[0]) {
			t.Fatalf("round trip changed value: %q -> %q -> %#v", text, out.Fields[0], again)
		}
	})
}

// FuzzCSVRoundTrip checks that stringified rows parse back unchanged.
func FuzzCSVRoundTrip(f *testing.F) {
	for _, s := range []string{"a,b\nc,d", "x\n\ny", "\"q\"\"uote\",\n", "line\r\nbreak,\rcarriage", ",,,", ""} {
		f.Add(s, byte(','), false)
	}
	f.Fuzz(func(t *testing.T, text string, delimiter byte, crlf bool) {
		if !utf8.ValidString(text) || strings.Contains(text, "\r\n") || delimiter >= 128 || strings.IndexByte("\"\r\n\x00", delimiter) >= 0 {
			t.Skip()
		}
		ending := "\n"
		if crlf {
			ending = "\r\n"
		}
		options := Record{"@std/CsvOptions", map[string]Value{"delimiter": string([]byte{delimiter}), "line_ending": ending}}
		var rows []Value
		for _, line := range strings.Split(text, "\n") {
			rows = append(rows, libraryStrings(strings.Split(line, string([]byte{delimiter}))))
		}
		list := libraryList("@std/List[String]", rows)
		out := libraryCall(t, "csv/stringify", list, options, int64(1<<20))
		if out.Tag != "ok" {
			t.Fatalf("stringify failed: %#v", out)
		}
		back := libraryCall(t, "csv/parse", out.Fields[0], options, int64(1<<20), int64(1<<20))
		if back.Tag != "ok" || !Equal(list, back.Fields[0]) {
			t.Fatalf("round trip changed rows: %q -> %q -> %#v", text, out.Fields[0], back)
		}
	})
}

func TestCSVStringifyKeepsCarriageReturns(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		options := Record{"@std/CsvOptions", map[string]Value{"delimiter": ",", "line_ending": ending}}
		rows := libraryList("@std/List[String]", []Value{libraryStrings([]string{"a\rb", "\r", "x\ny", ""}), libraryStrings([]string{""})})
		out := librarySuccess(t, libraryCall(t, "csv/stringify", rows, options, int64(1000)))
		back := librarySuccess(t, libraryCall(t, "csv/parse", out, options, int64(10), int64(10)))
		if !Equal(rows, back) {
			t.Fatalf("%q: %q changed rows", ending, out)
		}
	}
}
