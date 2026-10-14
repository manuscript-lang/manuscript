package msruntime

import (
	"encoding/json"
	"io"
	"math"
	"strconv"
	"strings"
)

// Generated programs register the declaration order of map-backed records
// (generic source records) and the field labels of alternative cases, which
// the dynamic values do not carry. Nongeneric source records are Structs and
// report their own order.
var (
	jsonRecordFields = map[string][]string{}
	jsonCaseFields   = map[string][]string{}
)

// RegisterRecordFields records a source record's field names in declaration order.
func RegisterRecordFields(typ string, fields []string) { jsonRecordFields[typ] = fields }

// RegisterCaseFields records the payload labels of one alternative case.
func RegisterCaseFields(typ, tag string, fields []string) { jsonCaseFields[typ+"."+tag] = fields }

// jsonEncoder writes any value the checker accepts under JsonEncodable.
type jsonEncoder struct {
	ctx    *Execution
	w      *libraryLimitedWriter
	active map[equalityIdentity]bool
}

func (e *jsonEncoder) write(s string) error { _, err := e.w.Write([]byte(s)); return err }

func (e *jsonEncoder) quote(s string) error {
	if int64(len(s)) > e.w.max-int64(e.w.Len()) {
		e.w.overflow = true
		return io.ErrShortBuffer
	}
	b, _ := json.Marshal(s)
	_, err := e.w.Write(b)
	return err
}

// enter marks a container as being written so a value reachable from itself
// is reported instead of recursing forever. The returned function leaves it.
func (e *jsonEncoder) enter(value Value) (func(), error) {
	identity, ok := equalityID(value)
	if !ok {
		return func() {}, nil
	}
	if alt, isAlt := value.(Alternative); isAlt && len(alt.Fields) == 0 {
		return func() {}, nil
	}
	if e.active[identity] {
		return nil, io.ErrUnexpectedEOF
	}
	e.active[identity] = true
	return func() { delete(e.active, identity) }, nil
}

func (e *jsonEncoder) number(text string) error {
	if text == "" || !json.Valid([]byte(text)) || text[0] != '-' && (text[0] < '0' || text[0] > '9') || text[len(text)-1] < '0' || text[len(text)-1] > '9' {
		return io.ErrUnexpectedEOF
	}
	return e.write(text)
}

// jsonFloat is the shortest decimal that parses back to f, using an exponent
// only for very large or small magnitudes.
func jsonFloat(f float64) (string, bool) {
	if math.IsNaN(f) || math.IsInf(f, 0) {
		return "", false
	}
	format := byte('f')
	if abs := math.Abs(f); abs != 0 && (abs < 1e-6 || abs >= 1e21) {
		format = 'e'
	}
	b := strconv.AppendFloat(nil, f, format, -1, 64)
	if format == 'e' {
		if n := len(b); n >= 4 && b[n-4] == 'e' && b[n-3] == '-' && b[n-2] == '0' {
			b[n-2] = b[n-1]
			b = b[:n-1]
		}
	}
	return string(b), true
}

func isNone(value Value) bool {
	alt, ok := value.(Alternative)
	return ok && alt.Tag == "none" && strings.HasPrefix(alt.Type, "@std/Optional")
}

// members writes object members in order, omitting Optional fields that are none.
func (e *jsonEncoder) members(names []string, get func(int) Value) error {
	first := true
	for i, name := range names {
		field := get(i)
		if isNone(field) {
			continue
		}
		if !first {
			if err := e.write(","); err != nil {
				return err
			}
		}
		first = false
		if err := e.quote(name); err != nil {
			return err
		}
		if err := e.write(":"); err != nil {
			return err
		}
		if err := e.value(field); err != nil {
			return err
		}
	}
	return nil
}

func (e *jsonEncoder) elements(items []Value) error {
	if err := e.write("["); err != nil {
		return err
	}
	for i, item := range items {
		if i > 0 {
			if err := e.write(","); err != nil {
				return err
			}
		}
		if err := e.value(item); err != nil {
			return err
		}
	}
	return e.write("]")
}

func (e *jsonEncoder) value(value Value) error {
	CheckCancelled(e.ctx)
	switch v := value.(type) {
	case string:
		return e.quote(v)
	case int64:
		return e.write(strconv.FormatInt(v, 10))
	case bool:
		return e.write(strconv.FormatBool(v))
	case float64:
		text, ok := jsonFloat(v)
		if !ok {
			return io.ErrUnexpectedEOF
		}
		return e.write(text)
	case Decimal:
		return e.number(v.String())
	case libraryBigInt:
		return e.number(v.n.String())
	case View:
		return e.value(v.Receiver)
	case *List:
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.elements(v.Boxed())
	case *Set:
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.elements(v.Items)
	case *Map:
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		if err := e.write("{"); err != nil {
			return err
		}
		for i, entry := range v.Entries {
			key, ok := entry.Key.(string)
			if !ok {
				return io.ErrUnexpectedEOF
			}
			if i > 0 {
				if err := e.write(","); err != nil {
					return err
				}
			}
			if err := e.quote(key); err != nil {
				return err
			}
			if err := e.write(":"); err != nil {
				return err
			}
			if err := e.value(entry.Value); err != nil {
				return err
			}
		}
		return e.write("}")
	case Struct:
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.object(v.StructNames(), v.StructGet)
	case Record:
		names, ok := jsonRecordFields[v.Type]
		if !ok {
			names, ok = jsonRecordFields[baseType(v.Type)]
		}
		if !ok {
			Panic("runtime invariant: no registered field order for record " + v.Type)
			return io.ErrUnexpectedEOF
		}
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.object(names, func(i int) Value { return readField(v.Fields, names[i]) })
	case Alternative:
		return e.alternative(v)
	}
	return io.ErrUnexpectedEOF
}

func (e *jsonEncoder) object(names []string, get func(int) Value) error {
	if err := e.write("{"); err != nil {
		return err
	}
	if err := e.members(names, get); err != nil {
		return err
	}
	return e.write("}")
}

func baseType(key string) string {
	name, _ := splitType(key)
	return name
}

func (e *jsonEncoder) alternative(v Alternative) error {
	switch baseType(v.Type) {
	case "@std/Optional":
		if v.Tag == "none" {
			return e.write("null")
		}
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.value(v.Fields[0])
	case "@std/JsonValue":
		return e.jsonValue(v)
	}
	if len(v.Fields) == 0 {
		return e.quote(v.Tag)
	}
	labels := jsonCaseFields[baseType(v.Type)+"."+v.Tag]
	if len(labels) != len(v.Fields) {
		Panic("runtime invariant: no registered payload labels for " + v.Type + "." + v.Tag)
		return io.ErrUnexpectedEOF
	}
	leave, err := e.enter(v)
	if err != nil {
		return err
	}
	defer leave()
	if err := e.write("{"); err != nil {
		return err
	}
	if err := e.quote(v.Tag); err != nil {
		return err
	}
	if err := e.write(":"); err != nil {
		return err
	}
	if err := e.object(labels, func(i int) Value { return v.Fields[i] }); err != nil {
		return err
	}
	return e.write("}")
}

// jsonValue writes a JsonValue exactly as stored; cycles are detected through
// its list or map payload because the wrapper itself is a fresh value.
func (e *jsonEncoder) jsonValue(v Alternative) error {
	switch v.Tag {
	case "Null":
		return e.write("null")
	case "BoolValue":
		return e.write(strconv.FormatBool(v.Fields[0].(bool)))
	case "StringValue":
		return e.quote(v.Fields[0].(string))
	case "NumberValue":
		return e.number(v.Fields[0].(string))
	case "ArrayValue", "ObjectValue":
		return e.value(v.Fields[0])
	}
	return io.ErrUnexpectedEOF
}

func libraryJSONStringify(ctx *Execution, r string, a []Value) Value {
	max := a[1].(int64)
	if max < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	e := &jsonEncoder{ctx: ctx, w: &libraryLimitedWriter{max: max}, active: map[equalityIdentity]bool{}}
	if err := e.value(a[0]); err != nil {
		if e.w.overflow {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryError(r, "InvalidData", "")
	}
	return libraryOK(r, e.w.String())
}
