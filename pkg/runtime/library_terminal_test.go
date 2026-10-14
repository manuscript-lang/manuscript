package msruntime

import (
	"reflect"
	"testing"
)

func decodeAll(chunks ...string) []terminalEvent {
	var decoder terminalDecoder
	var out []terminalEvent
	for _, chunk := range chunks {
		out = append(out, decoder.Feed([]byte(chunk))...)
	}
	return append(out, decoder.Flush()...)
}

func key(name string) terminalEvent { return terminalEvent{Kind: "key", Text: name} }

func TestTerminalDecoder(t *testing.T) {
	tests := []struct {
		name   string
		chunks []string
		want   []terminalEvent
	}{
		{"text coalesces", []string{"héllo"}, []terminalEvent{{Kind: "text", Text: "héllo"}}},
		{"split utf-8 scalar", []string{"\xe2\x82", "\xac"}, []terminalEvent{{Kind: "text", Text: "€"}}},
		{"invalid utf-8", []string{"a\xffb"}, []terminalEvent{{Kind: "text", Text: "a�b"}}},
		{"controls", []string{"\r\t\x7f\x03"}, []terminalEvent{key("enter"), key("tab"), key("backspace"), {Kind: "key", Text: "c", Ctrl: true}}},
		{"arrows", []string{"\x1b[A\x1bOB"}, []terminalEvent{key("up"), key("down")}},
		{"split csi", []string{"\x1b", "[", "3", "~"}, []terminalEvent{key("delete")}},
		{"modified arrow", []string{"\x1b[1;5C"}, []terminalEvent{{Kind: "key", Text: "right", Ctrl: true}}},
		{"shift tab", []string{"\x1b[Z"}, []terminalEvent{{Kind: "key", Text: "tab", Shift: true}}},
		{"alt key", []string{"\x1bx"}, []terminalEvent{{Kind: "key", Text: "x", Alt: true}}},
		{"lone escape resolves on flush", []string{"\x1b"}, []terminalEvent{key("escape")}},
		{"unknown sequence dropped", []string{"a\x1b[99xb"}, []terminalEvent{{Kind: "text", Text: "a"}, {Kind: "text", Text: "b"}}},
		{"function keys", []string{"\x1b[15~\x1bOP"}, []terminalEvent{key("f5"), key("f1")}},
	}
	for _, test := range tests {
		if got := decodeAll(test.chunks...); !reflect.DeepEqual(got, test.want) {
			t.Errorf("%s: got %+v want %+v", test.name, got, test.want)
		}
	}
}
