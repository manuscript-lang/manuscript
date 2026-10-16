package msruntime

import (
	"strconv"
	"strings"
)

// jsonScanner is a strict recursive-descent JSON reader. It keeps number text
// verbatim, rejects duplicate object keys, and counts every value against
// maxValues; surrogate escapes are validated beforehand by jsonUnicodeValid.
type jsonScanner struct {
	ctx       *Execution
	text      string
	pos       int
	count     int
	maxDepth  int
	maxValues int
	limitHit  bool
}

func (p *jsonScanner) skipSpace() {
	for p.pos < len(p.text) {
		switch p.text[p.pos] {
		case ' ', '\t', '\n', '\r':
			p.pos++
		default:
			return
		}
	}
}

func (p *jsonScanner) literal(word string) bool {
	if strings.HasPrefix(p.text[p.pos:], word) {
		p.pos += len(word)
		return true
	}
	return false
}

func (p *jsonScanner) value(depth int) (JsonValue, bool) {
	if p.count&255 == 0 {
		CheckCancelled(p.ctx)
	}
	p.count++
	if p.count > p.maxValues {
		p.limitHit = true
		return nil, false
	}
	p.skipSpace()
	if p.pos >= len(p.text) {
		return nil, false
	}
	switch c := p.text[p.pos]; {
	case c == 'n':
		return JsonValue_Null{}, p.literal("null")
	case c == 't':
		return JsonValue_BoolValue{Value: true}, p.literal("true")
	case c == 'f':
		return JsonValue_BoolValue{Value: false}, p.literal("false")
	case c == '"':
		s, ok := p.str()
		return JsonValue_StringValue{Value: s}, ok
	case c == '-' || (c >= '0' && c <= '9'):
		start := p.pos
		if !p.number() {
			return nil, false
		}
		return JsonValue_NumberValue{Text: p.text[start:p.pos]}, true
	case c == '[':
		return p.array(depth)
	case c == '{':
		return p.object(depth)
	}
	return nil, false
}

func (p *jsonScanner) digits() bool {
	start := p.pos
	for p.pos < len(p.text) && p.text[p.pos] >= '0' && p.text[p.pos] <= '9' {
		p.pos++
	}
	return p.pos > start
}

func (p *jsonScanner) number() bool {
	if p.text[p.pos] == '-' {
		p.pos++
	}
	if p.pos >= len(p.text) {
		return false
	}
	if p.text[p.pos] == '0' {
		p.pos++
	} else if !p.digits() {
		return false
	}
	if p.pos < len(p.text) && p.text[p.pos] == '.' {
		p.pos++
		if !p.digits() {
			return false
		}
	}
	if p.pos < len(p.text) && (p.text[p.pos] == 'e' || p.text[p.pos] == 'E') {
		p.pos++
		if p.pos < len(p.text) && (p.text[p.pos] == '+' || p.text[p.pos] == '-') {
			p.pos++
		}
		if !p.digits() {
			return false
		}
	}
	return true
}

// str reads a quoted string, returning a substring of the input when it has no
// escapes.
func (p *jsonScanner) str() (string, bool) {
	p.pos++
	start := p.pos
	for p.pos < len(p.text) {
		c := p.text[p.pos]
		switch {
		case c == '"':
			s := p.text[start:p.pos]
			p.pos++
			return s, true
		case c == '\\':
			return p.escapedStr(start)
		case c < 0x20:
			return "", false
		}
		p.pos++
	}
	return "", false
}

func (p *jsonScanner) escapedStr(start int) (string, bool) {
	var b strings.Builder
	b.WriteString(p.text[start:p.pos])
	for p.pos < len(p.text) {
		c := p.text[p.pos]
		switch {
		case c == '"':
			p.pos++
			return b.String(), true
		case c < 0x20:
			return "", false
		case c != '\\':
			b.WriteByte(c)
			p.pos++
			continue
		}
		p.pos++
		if p.pos >= len(p.text) {
			return "", false
		}
		switch e := p.text[p.pos]; e {
		case '"', '\\', '/':
			b.WriteByte(e)
		case 'b':
			b.WriteByte('\b')
		case 'f':
			b.WriteByte('\f')
		case 'n':
			b.WriteByte('\n')
		case 'r':
			b.WriteByte('\r')
		case 't':
			b.WriteByte('\t')
		case 'u':
			r, ok := p.hex4(p.pos + 1)
			if !ok {
				return "", false
			}
			p.pos += 4
			if r >= 0xD800 && r <= 0xDBFF {
				lo, ok := p.hex4(p.pos + 3)
				if !ok || p.text[p.pos+1] != '\\' || p.text[p.pos+2] != 'u' {
					return "", false
				}
				r = 0x10000 + (r-0xD800)<<10 + (lo - 0xDC00)
				p.pos += 6
			}
			b.WriteRune(r)
		default:
			return "", false
		}
		p.pos++
	}
	return "", false
}

func (p *jsonScanner) hex4(at int) (rune, bool) {
	if at+4 > len(p.text) {
		return 0, false
	}
	v, err := strconv.ParseUint(p.text[at:at+4], 16, 16)
	return rune(v), err == nil
}

func (p *jsonScanner) array(depth int) (JsonValue, bool) {
	if depth+1 > p.maxDepth {
		p.limitHit = true
		return nil, false
	}
	p.pos++
	var items []JsonValue
	p.skipSpace()
	if p.pos < len(p.text) && p.text[p.pos] == ']' {
		p.pos++
		return JsonValue_ArrayValue{Values: NewList(items...)}, true
	}
	for {
		item, ok := p.value(depth + 1)
		if !ok {
			return nil, false
		}
		items = append(items, item)
		p.skipSpace()
		if p.pos >= len(p.text) {
			return nil, false
		}
		c := p.text[p.pos]
		p.pos++
		if c == ']' {
			return JsonValue_ArrayValue{Values: NewList(items...)}, true
		}
		if c != ',' {
			return nil, false
		}
	}
}

func (p *jsonScanner) object(depth int) (JsonValue, bool) {
	if depth+1 > p.maxDepth {
		p.limitHit = true
		return nil, false
	}
	p.pos++
	m := NewMap[string, JsonValue]()
	p.skipSpace()
	if p.pos < len(p.text) && p.text[p.pos] == '}' {
		p.pos++
		return JsonValue_ObjectValue{Values: m}, true
	}
	for {
		p.skipSpace()
		if p.pos >= len(p.text) || p.text[p.pos] != '"' {
			return nil, false
		}
		key, ok := p.str()
		if !ok {
			return nil, false
		}
		if _, seen := m.Lookup(key); seen {
			return nil, false
		}
		p.skipSpace()
		if p.pos >= len(p.text) || p.text[p.pos] != ':' {
			return nil, false
		}
		p.pos++
		v, ok := p.value(depth + 1)
		if !ok {
			return nil, false
		}
		m.Put(key, v)
		p.skipSpace()
		if p.pos >= len(p.text) {
			return nil, false
		}
		c := p.text[p.pos]
		p.pos++
		if c == '}' {
			return JsonValue_ObjectValue{Values: m}, true
		}
		if c != ',' {
			return nil, false
		}
	}
}
