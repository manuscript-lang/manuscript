package msruntime

import (
	"strconv"
	"strings"
	"unicode/utf8"
)

// terminalEvent is one decoded input event. Kind is "text", "key", or "resize".
// For keys, Text is the key name.
type terminalEvent struct {
	Kind          string
	Text          string
	Ctrl, Alt     bool
	Shift         bool
	Columns, Rows int
}

// terminalDecoder turns terminal input bytes into events. Bytes of an
// incomplete UTF-8 scalar or escape sequence stay pending across Feed calls;
// Flush resolves a pending lone escape into the Escape key.
type terminalDecoder struct{ pending []byte }

func (d *terminalDecoder) Pending() bool { return len(d.pending) > 0 }

// Flush treats pending input as final: a lone escape is the Escape key and any
// other incomplete sequence is dropped.
func (d *terminalDecoder) Flush() []terminalEvent {
	var out []terminalEvent
	if len(d.pending) == 1 && d.pending[0] == 0x1b {
		out = append(out, terminalEvent{Kind: "key", Text: "escape"})
	}
	d.pending = nil
	return out
}

// Feed decodes data. Invalid UTF-8 becomes U+FFFD; unrecognized escape
// sequences are dropped whole so they never leak as text.
func (d *terminalDecoder) Feed(data []byte) []terminalEvent {
	buf := append(d.pending, data...)
	d.pending = nil
	var out []terminalEvent
	var text strings.Builder
	flush := func() {
		if text.Len() > 0 {
			out = append(out, terminalEvent{Kind: "text", Text: text.String()})
			text.Reset()
		}
	}
	for len(buf) > 0 {
		b := buf[0]
		switch {
		case b == 0x1b:
			flush()
			event, n, state := terminalEscape(buf)
			if state == terminalIncomplete {
				d.pending = append([]byte{}, buf...)
				return out
			}
			if state == terminalDecoded {
				out = append(out, event)
			}
			buf = buf[n:]
		case b < 0x20 || b == 0x7f:
			flush()
			out = append(out, terminalControl(b))
			buf = buf[1:]
		default:
			if !utf8.FullRune(buf) {
				flush()
				d.pending = append([]byte{}, buf...)
				return out
			}
			r, n := utf8.DecodeRune(buf)
			text.WriteRune(r)
			buf = buf[n:]
		}
	}
	flush()
	return out
}

func terminalControl(b byte) terminalEvent {
	switch b {
	case '\r', '\n':
		return terminalEvent{Kind: "key", Text: "enter"}
	case '\t':
		return terminalEvent{Kind: "key", Text: "tab"}
	case 0x7f, 0x08:
		return terminalEvent{Kind: "key", Text: "backspace"}
	case 0:
		return terminalEvent{Kind: "key", Text: "space", Ctrl: true}
	}
	if b <= 0x1a {
		return terminalEvent{Kind: "key", Text: string(rune('a' + b - 1)), Ctrl: true}
	}
	return terminalEvent{Kind: "key", Text: string(rune('@' + b)), Ctrl: true}
}

const (
	terminalIncomplete = iota
	terminalDecoded
	terminalDropped
)

var terminalTildeKeys = map[int]string{1: "home", 2: "insert", 3: "delete", 4: "end", 5: "page_up", 6: "page_down", 7: "home", 8: "end", 11: "f1", 12: "f2", 13: "f3", 14: "f4", 15: "f5", 17: "f6", 18: "f7", 19: "f8", 20: "f9", 21: "f10", 23: "f11", 24: "f12"}
var terminalLetterKeys = map[byte]string{'A': "up", 'B': "down", 'C': "right", 'D': "left", 'H': "home", 'F': "end", 'P': "f1", 'Q': "f2", 'R': "f3", 'S': "f4"}

// terminalEscape decodes the sequence at the start of buf, which begins with
// ESC, and returns the number of bytes consumed.
func terminalEscape(buf []byte) (terminalEvent, int, int) {
	if len(buf) == 1 {
		return terminalEvent{}, 0, terminalIncomplete
	}
	switch buf[1] {
	case '[':
		for i := 2; i < len(buf); i++ {
			c := buf[i]
			if c >= 0x40 && c <= 0x7e {
				event, ok := terminalCSI(string(buf[2:i]), c)
				if !ok {
					return event, i + 1, terminalDropped
				}
				return event, i + 1, terminalDecoded
			}
			if c < 0x20 || c > 0x3f {
				return terminalEvent{}, i, terminalDropped
			}
		}
		return terminalEvent{}, 0, terminalIncomplete
	case 'O':
		if len(buf) < 3 {
			return terminalEvent{}, 0, terminalIncomplete
		}
		if name, ok := terminalLetterKeys[buf[2]]; ok {
			return terminalEvent{Kind: "key", Text: name}, 3, terminalDecoded
		}
		return terminalEvent{}, 3, terminalDropped
	case 0x1b:
		return terminalEvent{Kind: "key", Text: "escape"}, 1, terminalDecoded
	}
	// Escape followed by a key is that key with Alt held.
	if !utf8.FullRune(buf[1:]) {
		return terminalEvent{}, 0, terminalIncomplete
	}
	r, n := utf8.DecodeRune(buf[1:])
	var event terminalEvent
	switch {
	case r < 0x20 || r == 0x7f:
		event = terminalControl(byte(r))
	case r == ' ':
		event = terminalEvent{Kind: "key", Text: "space"}
	default:
		event = terminalEvent{Kind: "key", Text: string(r)}
	}
	event.Alt = true
	return event, 1 + n, terminalDecoded
}

func terminalCSI(params string, final byte) (terminalEvent, bool) {
	numbers := []int{}
	for _, part := range strings.Split(params, ";") {
		n, _ := strconv.Atoi(part)
		numbers = append(numbers, n)
	}
	var event terminalEvent
	switch name, letter := terminalLetterKeys[final]; {
	case final == 'Z':
		return terminalEvent{Kind: "key", Text: "tab", Shift: true}, true
	case final == '~':
		tilde, ok := terminalTildeKeys[numbers[0]]
		if !ok {
			return event, false
		}
		event = terminalEvent{Kind: "key", Text: tilde}
	case letter:
		event = terminalEvent{Kind: "key", Text: name}
	default:
		return event, false
	}
	if len(numbers) > 1 && numbers[1] > 1 {
		bits := numbers[1] - 1
		event.Shift, event.Alt, event.Ctrl = bits&1 != 0, bits&2 != 0, bits&4 != 0
	}
	return event, true
}
