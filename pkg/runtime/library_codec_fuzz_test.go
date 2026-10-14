package msruntime

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func fuzzQueryEntries(pairs ...string) *List {
	items := make([]Value, 0, len(pairs)/2)
	for i := 0; i+1 < len(pairs); i += 2 {
		items = append(items, Record{"@std/QueryEntry", map[string]Value{"key": pairs[i], "value": pairs[i+1]}})
	}
	return libraryList("@std/QueryEntry", items)
}

// FuzzCodecRoundTrip checks each encoder against its decoder, and that any
// text a decoder accepts is canonical when encoded again.
func FuzzCodecRoundTrip(f *testing.F) {
	for _, s := range []string{"", "a b&c=d", "é🙂%/?#", "\x00\xff", "&amp;<>\"'", "Zg==", "_w==", "00FF"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		data := Bytes{[]byte(text)}
		limit := int64(1 << 20)
		hexText := libraryPlain(t, "encoding/hex_encode", data).(string)
		if got := librarySuccess(t, libraryCall(t, "encoding/hex_decode", hexText, limit)); !Equal(got, data) {
			t.Fatalf("hex round trip: %q", text)
		}
		for _, urlSafe := range []bool{false, true} {
			encoded := libraryPlain(t, "encoding/base64_encode", data, urlSafe).(string)
			if got := librarySuccess(t, libraryCall(t, "encoding/base64_decode", encoded, urlSafe, limit)); !Equal(got, data) {
				t.Fatalf("base64 round trip: %q url_safe=%v", text, urlSafe)
			}
			// A decoder accepts only canonical text, so re-encoding reproduces it.
			if decoded := libraryCall(t, "encoding/base64_decode", text, urlSafe, limit); decoded.Tag == "ok" {
				if again := libraryPlain(t, "encoding/base64_encode", decoded.Fields[0], urlSafe).(string); again != text {
					t.Fatalf("base64 accepted non-canonical %q, re-encodes to %q", text, again)
				}
			}
		}
		if decoded := libraryCall(t, "encoding/hex_decode", text, limit); decoded.Tag == "ok" {
			again := libraryPlain(t, "encoding/hex_encode", decoded.Fields[0]).(string)
			if !strings.EqualFold(again, text) {
				t.Fatalf("hex accepted %q, re-encodes to %q", text, again)
			}
		}
		if !utf8.ValidString(text) {
			return
		}
		component := libraryPlain(t, "url/encode_component", text).(string)
		if got := librarySuccess(t, libraryCall(t, "url/decode_component", component)); got != text {
			t.Fatalf("component round trip: %q -> %q -> %q", text, component, got)
		}
		entries := fuzzQueryEntries(text, text+"=&", "", text)
		query := libraryPlain(t, "url/format_query", entries).(string)
		back := librarySuccess(t, libraryCall(t, "url/parse_query", query, int64(1000)))
		if !Equal(entries, back) {
			t.Fatalf("query round trip: %q -> %q", text, query)
		}
		escaped := libraryPlain(t, "html/escape", text).(string)
		if got := libraryPlain(t, "html/unescape", escaped).(string); got != text {
			t.Fatalf("html round trip: %q -> %q -> %q", text, escaped, got)
		}
	})
}

// FuzzURLFormatStable checks that a parsed URL formats to text that parses to
// the same URL.
func FuzzURLFormatStable(f *testing.F) {
	for _, s := range []string{"http://example.com/a b?x=1#f", "https://[::1]:8080/p%2Fq", "/relative?x", "mailto:a@b", "http://h/%zz", "//host/path"} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, text string) {
		parsed := libraryCall(t, "url/parse", text)
		if parsed.Tag != "ok" {
			return
		}
		value := parsed.Fields[0]
		formatted := libraryCall(t, "url/format", value)
		if formatted.Tag != "ok" {
			return
		}
		again := libraryCall(t, "url/parse", formatted.Fields[0])
		if again.Tag != "ok" || !Equal(value, again.Fields[0]) {
			t.Fatalf("%q formats to %q which parses to %#v", text, formatted.Fields[0], again)
		}
	})
}
