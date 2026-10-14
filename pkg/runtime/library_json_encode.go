package msruntime

import (
	"encoding/base64"
	"encoding/json"
	"io"
	"math"
	"strconv"
	"strings"
	"time"
)

// Generated programs register the declaration order of map-backed records
// (generic source records and every standard record) and the field labels of
// alternative cases, which the dynamic values do not carry. Nongeneric source
// records are Structs and report their own order.
var (
	jsonRecordFields = map[string][]string{}
	jsonCaseFields   = map[string][]string{}
)

// RegisterRecordFields records a record's field names in declaration order.
func RegisterRecordFields(typ string, fields []string) { jsonRecordFields[typ] = fields }

// RegisterCaseFields records the payload labels of one alternative case.
func RegisterCaseFields(typ, tag string, fields []string) { jsonCaseFields[typ+"."+tag] = fields }

// jsonMaxIndent is the widest indentation, as in JavaScript's JSON.stringify.
const jsonMaxIndent = 10

// errJSONNoForm marks a value that has no JSON form: a function, a resource, a
// Unit or a monotonic Instant. Containers omit it or write null for it; at the
// root it is an error.
var errJSONNoForm = io.ErrNoProgress

// jsonEncoder writes any Manuscript value as JSON text.
type jsonEncoder struct {
	ctx    *Execution
	w      *libraryLimitedWriter
	active map[equalityIdentity]bool
	indent string
	depth  int
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

// newline starts a new indented line at the current depth; compact output has none.
func (e *jsonEncoder) newline() error {
	if e.indent == "" {
		return nil
	}
	return e.write("\n" + strings.Repeat(e.indent, e.depth))
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
// only for very large or small magnitudes. NaN and infinities have no number
// form, so the caller writes null.
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

func baseType(key string) string {
	name, _ := splitType(key)
	return name
}

func isOptional(alt Alternative) bool { return baseType(alt.Type) == "@std/Optional" }

func isNone(value Value) bool {
	alt, ok := value.(Alternative)
	return ok && alt.Tag == "none" && isOptional(alt)
}

// jsonUnwrap drops contract views, which only select a method set.
func jsonUnwrap(value Value) Value {
	for {
		view, ok := value.(View)
		if !ok {
			return value
		}
		value = view.Receiver
	}
}

// jsonNoForm reports whether a value has no JSON form once Optional wrappers
// are looked through. A none inside some(none) is a present null, not absent.
func jsonNoForm(value Value) bool {
	for {
		value = jsonUnwrap(value)
		if alt, ok := value.(Alternative); ok && isOptional(alt) {
			if alt.Tag == "none" {
				return false
			}
			value = alt.Fields[0]
			continue
		}
		break
	}
	switch value.(type) {
	case string, int64, bool, float64, Decimal, libraryBigInt, Bytes, Duration, libraryTimestamp, libraryIPAddress, libraryCidr, *List, *Set, *Map, Struct, Record, Alternative:
		return false
	}
	return true
}

// jsonKey is the member name for a Map key, as JavaScript turns an object key
// into its string form. Only scalar keys have one.
func jsonKey(key Value) (string, bool) {
	switch k := jsonUnwrap(key).(type) {
	case string:
		return k, true
	case int64:
		return strconv.FormatInt(k, 10), true
	case bool:
		return strconv.FormatBool(k), true
	case float64:
		switch {
		case math.IsNaN(k):
			return "NaN", true
		case math.IsInf(k, 1):
			return "Infinity", true
		case math.IsInf(k, -1):
			return "-Infinity", true
		}
		text, _ := jsonFloat(k)
		return text, true
	case Decimal:
		return k.String(), true
	case libraryBigInt:
		return k.n.String(), true
	case Duration:
		return strconv.FormatInt(int64(k), 10), true
	case libraryTimestamp:
		return k.t.UTC().Format(time.RFC3339Nano), true
	case libraryIPAddress:
		return k.address.String(), true
	case libraryCidr:
		return k.prefix.String(), true
	case Alternative:
		if len(k.Fields) == 0 && !isOptional(k) {
			return k.Tag, true
		}
	}
	return "", false
}

// member writes one present member, preceded by a comma after the first.
func (e *jsonEncoder) member(first *bool, name string, value Value) error {
	if !*first {
		if err := e.write(","); err != nil {
			return err
		}
	}
	*first = false
	if err := e.newline(); err != nil {
		return err
	}
	if err := e.quote(name); err != nil {
		return err
	}
	colon := ":"
	if e.indent != "" {
		colon = ": "
	}
	if err := e.write(colon); err != nil {
		return err
	}
	return e.value(value)
}

// object writes the members for which omit is false, in order.
func (e *jsonEncoder) object(names []string, get func(int) Value, omit func(Value) bool) error {
	if err := e.write("{"); err != nil {
		return err
	}
	e.depth++
	first := true
	for i, name := range names {
		field := get(i)
		if omit(field) {
			continue
		}
		if err := e.member(&first, name, field); err != nil {
			return err
		}
	}
	e.depth--
	if !first {
		if err := e.newline(); err != nil {
			return err
		}
	}
	return e.write("}")
}

// omitField reports whether a record field is left out: an Optional none or a
// value with no JSON form.
func omitField(value Value) bool { return isNone(jsonUnwrap(value)) || jsonNoForm(value) }

// omitEntry is the same for Map values, where none is written as null.
func omitEntry(value Value) bool { return jsonNoForm(value) }

func (e *jsonEncoder) elements(items []Value) error {
	if err := e.write("["); err != nil {
		return err
	}
	e.depth++
	for i, item := range items {
		if i > 0 {
			if err := e.write(","); err != nil {
				return err
			}
		}
		if err := e.newline(); err != nil {
			return err
		}
		if jsonNoForm(item) {
			if err := e.write("null"); err != nil {
				return err
			}
			continue
		}
		if err := e.value(item); err != nil {
			return err
		}
	}
	e.depth--
	if len(items) > 0 {
		if err := e.newline(); err != nil {
			return err
		}
	}
	return e.write("]")
}

// hook runs a value's JsonEncode.to_json when it implements one.
func (e *jsonEncoder) hook(value Value, scope TypeScope) (Value, bool) {
	if len(implementationsByName["to_json"]) == 0 {
		return nil, false
	}
	method, ok := implementationFunction(value, "@std/JsonEncode", "to_json", scope)
	if !ok {
		return nil, false
	}
	return Invoke(e.ctx, method, nil), true
}

func (e *jsonEncoder) value(value Value) error {
	CheckCancelled(e.ctx)
	scope := e.ctx.EqualityScope
	if view, ok := value.(View); ok {
		scope = view.Scope
		if view.Type == "@std/Error" {
			return e.errorValue(view)
		}
		value = jsonUnwrap(view)
	}
	switch v := value.(type) {
	case Struct, Record:
		if result, ok := e.hook(v, scope); ok {
			return e.value(result)
		}
	case Alternative:
		if baseType(v.Type) != "@std/JsonValue" {
			if result, ok := e.hook(v, scope); ok {
				return e.value(result)
			}
		}
	}
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
			return e.write("null")
		}
		return e.write(text)
	case Decimal:
		return e.number(v.String())
	case libraryBigInt:
		return e.number(v.n.String())
	case Duration:
		return e.write(strconv.FormatInt(int64(v), 10))
	case libraryTimestamp:
		return e.quote(v.t.UTC().Format(time.RFC3339Nano))
	case libraryIPAddress:
		return e.quote(v.address.String())
	case libraryCidr:
		return e.quote(v.prefix.String())
	case Bytes:
		return e.quote(base64.StdEncoding.EncodeToString(v.Items))
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
		return e.mapValue(v)
	case Struct:
		leave, err := e.enter(v)
		if err != nil {
			return err
		}
		defer leave()
		return e.object(v.StructNames(), v.StructGet, omitField)
	case Record:
		return e.record(v)
	case Alternative:
		return e.alternative(v)
	}
	return errJSONNoForm
}

func (e *jsonEncoder) mapValue(m *Map) error {
	keys := make([]string, len(m.Entries))
	for i, entry := range m.Entries {
		key, ok := jsonKey(entry.Key)
		if !ok {
			return io.ErrUnexpectedEOF
		}
		keys[i] = key
	}
	return e.object(keys, func(i int) Value { return m.Entries[i].Value }, omitEntry)
}

func (e *jsonEncoder) record(v Record) error {
	if v.Type == "@std/Url" {
		u, err := libraryURL(v)
		if err != nil {
			return io.ErrUnexpectedEOF
		}
		return e.quote(u.String())
	}
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
	return e.object(names, func(i int) Value { return readField(v.Fields, names[i]) }, omitField)
}

// errorValue writes a value held as an Error: an object with its message.
func (e *jsonEncoder) errorValue(view View) error {
	message, ok := Invoke(e.ctx, Bind(view, "@std/Error", "message"), nil).(string)
	if !ok {
		return io.ErrUnexpectedEOF
	}
	return e.object([]string{"message"}, func(int) Value { return message }, omitField)
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
	// {"Case":{"label":value}}: the case name keys its labeled payload, so a
	// structural encoding round-trips and equal labels in two cases stay distinct.
	if err := e.write("{"); err != nil {
		return err
	}
	e.depth++
	if err := e.newline(); err != nil {
		return err
	}
	if err := e.quote(v.Tag); err != nil {
		return err
	}
	colon := ":"
	if e.indent != "" {
		colon = ": "
	}
	if err := e.write(colon); err != nil {
		return err
	}
	if err := e.object(labels, func(i int) Value { return v.Fields[i] }, omitField); err != nil {
		return err
	}
	e.depth--
	if err := e.newline(); err != nil {
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
	max, indent := a[1].(int64), a[2].(int64)
	if max < 0 || indent < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	e := &jsonEncoder{ctx: ctx, w: &libraryLimitedWriter{max: max}, active: map[equalityIdentity]bool{}}
	e.indent = strings.Repeat(" ", int(min(indent, jsonMaxIndent)))
	if err := e.value(a[0]); err != nil {
		if e.w.overflow {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryError(r, "InvalidData", "")
	}
	return libraryOK(r, e.w.String())
}
