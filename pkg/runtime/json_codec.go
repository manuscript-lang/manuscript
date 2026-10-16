package msruntime

import (
	"encoding/base64"
	"encoding/json"
	"math"
	"math/big"
	"strconv"

	"github.com/manuscript-lang/manuscript/internal/decimal"
)

// JsonScope carries one stringify call: the execution to poll for
// cancellation and the containers being encoded, so a cycle fails instead of
// recursing forever.
type JsonScope struct {
	ctx    *Execution
	active map[any]struct{}
	// Failed is set when the value cannot be encoded at all, as for a cycle.
	Failed bool
}

// NewJsonScope starts an encode.
func NewJsonScope(ctx *Execution) *JsonScope {
	return &JsonScope{ctx: ctx, active: map[any]struct{}{}}
}

// Enter marks container p active. It reports false, and fails the encode, when
// p is already being encoded or the nesting is deeper than parse accepts.
func (s *JsonScope) Enter(p any) bool {
	CheckCancelled(s.ctx)
	if _, seen := s.active[p]; seen || len(s.active) >= jsonDepthCeiling {
		s.Failed = true
		return false
	}
	s.active[p] = struct{}{}
	return true
}

// Ctx is the execution the encode runs in, for JsonEncode implementations.
func (s *JsonScope) Ctx() *Execution { return s.ctx }

// Leave unmarks a container.
func (s *JsonScope) Leave(p any) { delete(s.active, p) }

// JsonEnc is the shape of a generated encoder: false means the value has no
// JSON form.
type JsonEnc[T any] = func(*JsonScope, T) (JsonValue, bool)

func JsonEncInt(_ *JsonScope, v int64) (JsonValue, bool) {
	return JsonValue_NumberValue{Text: strconv.FormatInt(v, 10)}, true
}

// JsonEncFloat writes the shortest round-trip form; NaN and infinities are null.
func JsonEncFloat(_ *JsonScope, v float64) (JsonValue, bool) {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return JsonValue_Null{}, true
	}
	b, _ := json.Marshal(v)
	return JsonValue_NumberValue{Text: string(b)}, true
}

func JsonEncBool(_ *JsonScope, v bool) (JsonValue, bool) { return JsonValue_BoolValue{Value: v}, true }

func JsonEncString(_ *JsonScope, v string) (JsonValue, bool) {
	return JsonValue_StringValue{Value: v}, true
}

// JsonEncValue passes a JsonValue through.
func JsonEncValue(_ *JsonScope, v JsonValue) (JsonValue, bool) { return v, true }

// JsonEncNone is the encoder of types with no JSON form: functions, handles
// and Unit.
func JsonEncNone[T any](*JsonScope, T) (JsonValue, bool) { return nil, false }

// JsonEncNative encodes the standard value types that have a fixed text or
// number form.
func JsonEncNative[T any](_ *JsonScope, v T) (JsonValue, bool) {
	switch x := any(v).(type) {
	case *BigInt:
		return JsonValue_NumberValue{Text: x.String()}, true
	case *Decimal:
		return JsonValue_NumberValue{Text: x.String()}, true
	case Duration:
		return JsonValue_NumberValue{Text: strconv.FormatInt(int64(x), 10)}, true
	case Timestamp:
		return JsonValue_StringValue{Value: x.String()}, true
	case *Bytes:
		return JsonValue_StringValue{Value: base64.StdEncoding.EncodeToString(x.Data)}, true
	case *IpAddress:
		return JsonValue_StringValue{Value: x.addr.String()}, true
	case *Cidr:
		return JsonValue_StringValue{Value: x.prefix.String()}, true
	case *Url:
		if r := Url_Format(nil, x); !r.Failed {
			return JsonValue_StringValue{Value: r.Val}, true
		}
	}
	return nil, false
}

// JsonKey is the object member name of a Map key: a scalar written as its text.
func JsonKey[K any](k K) (string, bool) {
	switch x := any(k).(type) {
	case string:
		return x, true
	case int64:
		return strconv.FormatInt(x, 10), true
	case bool:
		return strconv.FormatBool(x), true
	case float64:
		if math.IsNaN(x) || math.IsInf(x, 0) {
			return "", false
		}
		b, _ := json.Marshal(x)
		return string(b), true
	}
	if v, ok := JsonEncNative(nil, k); ok {
		switch n := v.(type) {
		case JsonValue_StringValue:
			return n.Value, true
		case JsonValue_NumberValue:
			return n.Text, true
		}
	}
	return "", false
}

func JsonEncList[T any](s *JsonScope, l *List[T], enc JsonEnc[T]) (JsonValue, bool) {
	return jsonEncItems(s, l.Items, enc)
}

func JsonEncSet[T comparable](s *JsonScope, set *Set[T], enc JsonEnc[T]) (JsonValue, bool) {
	return jsonEncItems(s, set.Snapshot(), enc)
}

func jsonEncItems[T any](s *JsonScope, items []T, enc JsonEnc[T]) (JsonValue, bool) {
	out := make([]JsonValue, 0, len(items))
	for _, x := range items {
		CheckCancelled(s.ctx)
		v, ok := enc(s, x)
		if s.Failed {
			return nil, false
		}
		if !ok {
			v = JsonValue_Null{}
		}
		out = append(out, v)
	}
	return JsonValue_ArrayValue{Values: NewList(out...)}, true
}

// JsonEncMap writes a Map as an object; key turns a map key into its member name.
func JsonEncMap[K comparable, V any](s *JsonScope, m *Map[K, V], key func(K) (string, bool), enc JsonEnc[V]) (JsonValue, bool) {
	out := NewMap[string, JsonValue]()
	for _, e := range m.Snapshot() {
		CheckCancelled(s.ctx)
		name, ok := key(e.Key)
		if !ok {
			return nil, false
		}
		v, ok := enc(s, e.Value)
		if s.Failed {
			return nil, false
		}
		if ok {
			out.Put(name, v)
		}
	}
	return JsonValue_ObjectValue{Values: out}, true
}

// JsonEncOption writes none as null and some as its payload.
func JsonEncOption[T any](s *JsonScope, o Option[T], enc JsonEnc[T]) (JsonValue, bool) {
	if !o.Some {
		return JsonValue_Null{}, true
	}
	return enc(s, o.Val)
}

// JsonField adds a member when the field has a JSON form.
func JsonField[T any](s *JsonScope, m *Map[string, JsonValue], name string, v T, enc JsonEnc[T]) {
	if s.Failed {
		return
	}
	if j, ok := enc(s, v); ok {
		m.Put(name, j)
	}
}

// JsonOptField adds a member for a present Optional field and omits an absent one.
func JsonOptField[T any](s *JsonScope, m *Map[string, JsonValue], name string, o Option[T], enc JsonEnc[T]) {
	if o.Some {
		JsonField(s, m, name, o.Val, enc)
	}
}

// JsonObject finishes a record or payload object.
func JsonObject(s *JsonScope, m *Map[string, JsonValue]) (JsonValue, bool) {
	if s.Failed {
		return nil, false
	}
	return JsonValue_ObjectValue{Values: m}, true
}

// JsonTagged is an alternative case with a payload: {"Case": {payload}}.
func JsonTagged(s *JsonScope, name string, payload *Map[string, JsonValue]) (JsonValue, bool) {
	if s.Failed {
		return nil, false
	}
	out := NewMap[string, JsonValue]()
	out.Put(name, JsonValue_ObjectValue{Values: payload})
	return JsonValue_ObjectValue{Values: out}, true
}

// JsonCase is an alternative case without a payload: the case name as a string.
func JsonCase(name string) (JsonValue, bool) { return JsonValue_StringValue{Value: name}, true }

// JsonReader carries one parse call's execution for generated decoders.
type JsonReader struct{ ctx *Execution }

// NewJsonReader starts a decode.
func NewJsonReader(ctx *Execution) *JsonReader { return &JsonReader{ctx: ctx} }

// Ctx is the execution the decode runs in, for field default expressions.
func (r *JsonReader) Ctx() *Execution { return r.ctx }

// JsonDec is the shape of a generated decoder: false means the JSON does not
// fit the type.
type JsonDec[T any] = func(*JsonReader, JsonValue) (T, bool)

func JsonDecInt(_ *JsonReader, j JsonValue) (int64, bool) {
	n, ok := j.(JsonValue_NumberValue)
	if !ok {
		return 0, false
	}
	v, err := strconv.ParseInt(n.Text, 10, 64)
	return v, err == nil
}

func JsonDecFloat(_ *JsonReader, j JsonValue) (float64, bool) {
	n, ok := j.(JsonValue_NumberValue)
	if !ok {
		return 0, false
	}
	v, err := strconv.ParseFloat(n.Text, 64)
	if err != nil || math.IsInf(v, 0) || math.IsNaN(v) {
		return 0, false
	}
	return v, true
}

func JsonDecBool(_ *JsonReader, j JsonValue) (bool, bool) {
	b, ok := j.(JsonValue_BoolValue)
	return b.Value, ok
}

func JsonDecString(_ *JsonReader, j JsonValue) (string, bool) {
	s, ok := j.(JsonValue_StringValue)
	return s.Value, ok
}

// JsonDecValue passes a JsonValue through.
func JsonDecValue(_ *JsonReader, j JsonValue) (JsonValue, bool) { return j, true }

// JsonDecNone is the decoder of types that cannot be read: functions, handles
// and Unit.
func JsonDecNone[T any](*JsonReader, JsonValue) (T, bool) {
	var zero T
	return zero, false
}

// JsonDecNative decodes the standard value types written by JsonEncNative.
func JsonDecNative[T any](_ *JsonReader, j JsonValue) (T, bool) {
	var zero T
	var out any
	var ok bool
	switch any(zero).(type) {
	case *BigInt:
		out, ok = jsonBigInt(j)
	case *Decimal:
		out, ok = jsonDecimal(j)
	case Duration:
		var n int64
		n, ok = JsonDecInt(nil, j)
		out = Duration(n)
	case Timestamp:
		if s, isString := j.(JsonValue_StringValue); isString {
			if r := Time_ParseTimestamp(nil, s.Value); !r.Failed {
				out, ok = r.Val, true
			}
		}
	case *Bytes:
		if s, isString := j.(JsonValue_StringValue); isString {
			if data, err := base64.StdEncoding.DecodeString(s.Value); err == nil {
				out, ok = &Bytes{Data: data}, true
			}
		}
	case *IpAddress:
		if s, isString := j.(JsonValue_StringValue); isString {
			if r := Net_ParseIp(nil, s.Value); !r.Failed {
				out, ok = r.Val, true
			}
		}
	case *Cidr:
		if s, isString := j.(JsonValue_StringValue); isString {
			if r := Net_ParseCidr(nil, s.Value); !r.Failed {
				out, ok = r.Val, true
			}
		}
	case *Url:
		if s, isString := j.(JsonValue_StringValue); isString {
			if r := Url_Parse(nil, s.Value); !r.Failed {
				out, ok = r.Val, true
			}
		}
	}
	if !ok {
		return zero, false
	}
	return out.(T), true
}

// jsonDigitsCeiling bounds the digits of a BigInt or Decimal read from JSON.
const jsonDigitsCeiling = 10000

func jsonBigInt(j JsonValue) (*BigInt, bool) {
	n, ok := j.(JsonValue_NumberValue)
	if !ok || len(n.Text) > jsonDigitsCeiling {
		return nil, false
	}
	v, ok := new(big.Int).SetString(n.Text, 10)
	if !ok {
		return nil, false
	}
	return &BigInt{n: v}, true
}

func jsonDecimal(j JsonValue) (*Decimal, bool) {
	n, ok := j.(JsonValue_NumberValue)
	if !ok || len(n.Text) > jsonDigitsCeiling {
		return nil, false
	}
	coefficient, exponent, negative, valid := decimal.Parts(n.Text)
	if !valid || exponent > jsonDigitsCeiling || exponent < -jsonDigitsCeiling {
		return nil, false
	}
	if coefficient == "0" {
		return &Decimal{new(big.Rat)}, true
	}
	if negative {
		coefficient = "-" + coefficient
	}
	v, ok := new(big.Rat).SetString(coefficient + "e" + strconv.Itoa(exponent))
	return &Decimal{v}, ok
}

// JsonParseKey reads an object member name as a Map key of type K.
func JsonParseKey[K any](r *JsonReader, text string) (K, bool) {
	var zero K
	switch any(zero).(type) {
	case string:
		return any(text).(K), true
	case int64:
		v, err := strconv.ParseInt(text, 10, 64)
		return any(v).(K), err == nil
	case bool:
		v, err := strconv.ParseBool(text)
		return any(v).(K), err == nil && (text == "true" || text == "false")
	case float64:
		v, ok := JsonDecFloat(r, JsonValue_NumberValue{Text: text})
		return any(v).(K), ok
	}
	if v, ok := JsonDecNative[K](r, JsonValue_StringValue{Value: text}); ok {
		return v, true
	}
	return JsonDecNative[K](r, JsonValue_NumberValue{Text: text})
}

func JsonDecList[T any](r *JsonReader, j JsonValue, dec JsonDec[T]) (*List[T], bool) {
	items, ok := jsonDecItems(r, j, dec)
	return NewList(items...), ok
}

func JsonDecSet[T comparable](r *JsonReader, j JsonValue, keys *Keys[T], dec JsonDec[T]) (*Set[T], bool) {
	items, ok := jsonDecItems(r, j, dec)
	return NewSetWith(keys, items...), ok
}

func jsonDecItems[T any](r *JsonReader, j JsonValue, dec JsonDec[T]) ([]T, bool) {
	a, ok := j.(JsonValue_ArrayValue)
	if !ok {
		return nil, false
	}
	out := make([]T, 0, len(a.Values.Items))
	for _, x := range a.Values.Items {
		CheckCancelled(r.ctx)
		v, ok := dec(r, x)
		if !ok {
			return nil, false
		}
		out = append(out, v)
	}
	return out, true
}

// JsonDecMap reads an object as a Map. Two members that read as the same key,
// such as "1" and "01", fail.
func JsonDecMap[K comparable, V any](r *JsonReader, j JsonValue, keys *Keys[K], parse func(*JsonReader, string) (K, bool), dec JsonDec[V]) (*Map[K, V], bool) {
	o, ok := j.(JsonValue_ObjectValue)
	if !ok {
		return nil, false
	}
	out := NewMapWith[K, V](keys)
	for _, e := range o.Values.Snapshot() {
		CheckCancelled(r.ctx)
		key, ok := parse(r, e.Key)
		if !ok {
			return nil, false
		}
		v, ok := dec(r, e.Value)
		if !ok {
			return nil, false
		}
		before := out.Len()
		out.Put(key, v)
		if out.Len() == before {
			return nil, false
		}
	}
	return out, true
}

// JsonDecOption reads null as none and anything else as the payload.
func JsonDecOption[T any](r *JsonReader, j JsonValue, dec JsonDec[T]) (Option[T], bool) {
	if _, null := j.(JsonValue_Null); null {
		return Option[T]{}, true
	}
	v, ok := dec(r, j)
	return Option[T]{Val: v, Some: ok}, ok
}

// JsonObjectOf is the members of an object value.
func JsonObjectOf(j JsonValue) (*Map[string, JsonValue], bool) {
	o, ok := j.(JsonValue_ObjectValue)
	return o.Values, ok
}

// JsonDecField reads member name through dec. found reports whether the member
// exists; ok is false when it exists but does not decode.
func JsonDecField[T any](r *JsonReader, o *Map[string, JsonValue], name string, dec JsonDec[T]) (v T, found, ok bool) {
	j, found := o.Lookup(name)
	if !found {
		return v, false, true
	}
	v, ok = dec(r, j)
	return v, true, ok
}

// JsonTag splits an alternative: a bare string names a case without payload,
// and a one-member object names a case and holds its payload.
func JsonTag(j JsonValue) (name string, payload *Map[string, JsonValue], ok bool) {
	switch v := j.(type) {
	case JsonValue_StringValue:
		return v.Value, nil, true
	case JsonValue_ObjectValue:
		if v.Values.Len() != 1 {
			return "", nil, false
		}
		e := v.Values.Snapshot()[0]
		p, isObject := e.Value.(JsonValue_ObjectValue)
		return e.Key, p.Values, isObject
	}
	return "", nil, false
}
