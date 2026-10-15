package rt

import (
	"encoding/json"
	"io"
	"math"
	"strconv"
	"strings"
)

// jsonDepthCeiling is the deepest container nesting Json_Parse accepts; the
// parser recurses per container, so an unset depth budget still stops here.
const jsonDepthCeiling = 100000

// Json_Parse parses one JSON value, retaining exact number text and rejecting
// duplicate object keys, trailing values and unpaired surrogate escapes.
func Json_Parse(ctx *Execution, text string, limits Option[*JsonLimits]) Result[JsonValue, JsonError] {
	maxBytes, maxDepth, maxValues := int64(math.MaxInt64), int64(math.MaxInt64), int64(math.MaxInt64)
	if limits.Some {
		maxBytes, maxDepth, maxValues = dfBudget(limits.Val.MaxBytes), dfBudget(limits.Val.MaxDepth), dfBudget(limits.Val.MaxValues)
	}
	if maxBytes < 0 || maxDepth < 0 || maxValues < 0 {
		return Fail[JsonValue, JsonError](JsonError_InvalidInput{})
	}
	if int64(len(text)) > maxBytes {
		return Fail[JsonValue, JsonError](JsonError_LimitExceeded{})
	}
	if maxDepth > jsonDepthCeiling {
		maxDepth = jsonDepthCeiling
	}
	// Go's decoder replaces unpaired surrogate escapes; reject them first.
	if !jsonUnicodeValid(ctx, text) {
		return Fail[JsonValue, JsonError](JsonError_InvalidData{})
	}
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	count := int64(0)
	limitHit := false
	var parse func(int64) (JsonValue, error)
	parse = func(depth int64) (JsonValue, error) {
		CheckCancelled(ctx)
		count++
		if count > maxValues {
			limitHit = true
			return nil, io.ErrShortBuffer
		}
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		switch v := token.(type) {
		case nil:
			return JsonValue_Null{}, nil
		case bool:
			return JsonValue_BoolValue{Value: v}, nil
		case string:
			return JsonValue_StringValue{Value: v}, nil
		case json.Number:
			return JsonValue_NumberValue{Text: string(v)}, nil
		case json.Delim:
			if depth+1 > maxDepth {
				limitHit = true
				return nil, io.ErrShortBuffer
			}
			if v == '[' {
				var items []JsonValue
				for decoder.More() {
					item, err := parse(depth + 1)
					if err != nil {
						return nil, err
					}
					items = append(items, item)
				}
				end, err := decoder.Token()
				if err != nil || end != json.Delim(']') {
					return nil, io.ErrUnexpectedEOF
				}
				return JsonValue_ArrayValue{Values: NewList(items...)}, nil
			}
			if v == '{' {
				m := NewMap[string, JsonValue]()
				for decoder.More() {
					key, err := decoder.Token()
					if err != nil {
						return nil, err
					}
					s, ok := key.(string)
					if _, seen := m.Lookup(s); !ok || seen {
						return nil, io.ErrUnexpectedEOF
					}
					value, err := parse(depth + 1)
					if err != nil {
						return nil, err
					}
					m.Put(s, value)
				}
				end, err := decoder.Token()
				if err != nil || end != json.Delim('}') {
					return nil, io.ErrUnexpectedEOF
				}
				return JsonValue_ObjectValue{Values: m}, nil
			}
		}
		return nil, io.ErrUnexpectedEOF
	}
	value, err := parse(0)
	if err != nil {
		if limitHit {
			return Fail[JsonValue, JsonError](JsonError_LimitExceeded{})
		}
		return Fail[JsonValue, JsonError](JsonError_InvalidData{})
	}
	if _, err := decoder.Token(); err != io.EOF {
		return Fail[JsonValue, JsonError](JsonError_InvalidData{})
	}
	return Ok[JsonValue, JsonError](value)
}

func jsonUnicodeValid(ctx *Execution, s string) bool {
	inString := false
	for i := 0; i < len(s); i++ {
		if i%4096 == 0 {
			CheckCancelled(ctx)
		}
		if s[i] == '"' {
			inString = !inString
			continue
		}
		if !inString || s[i] != '\\' {
			continue
		}
		i++
		if i >= len(s) {
			return false
		}
		if s[i] != 'u' {
			continue
		}
		if i+4 >= len(s) {
			return false
		}
		v, err := strconv.ParseUint(s[i+1:i+5], 16, 16)
		if err != nil {
			return false
		}
		i += 4
		if v >= 0xDC00 && v <= 0xDFFF {
			return false
		}
		if v >= 0xD800 && v <= 0xDBFF {
			if i+6 >= len(s) || s[i+1:i+3] != "\\u" {
				return false
			}
			lo, err := strconv.ParseUint(s[i+3:i+7], 16, 16)
			if err != nil || lo < 0xDC00 || lo > 0xDFFF {
				return false
			}
			i += 6
		}
	}
	return true
}

// Json_Stringify serializes compact JSON, escaping <, > and &, validating
// number text and rejecting cyclic values. maxBytes bounds the output.
func Json_Stringify(ctx *Execution, value JsonValue, maxBytes Option[int64]) Result[string, JsonError] {
	max := dfBudget(maxBytes)
	if max < 0 {
		return Fail[string, JsonError](JsonError_InvalidInput{})
	}
	w := &dfLimitedWriter{max: max}
	activeLists := map[*List[JsonValue]]bool{}
	activeMaps := map[*Map[string, JsonValue]]bool{}
	write := func(s string) error { _, err := w.Write([]byte(s)); return err }
	var emit func(JsonValue) error
	emit = func(value JsonValue) error {
		CheckCancelled(ctx)
		switch v := value.(type) {
		case JsonValue_Null:
			return write("null")
		case JsonValue_BoolValue:
			return write(strconv.FormatBool(v.Value))
		case JsonValue_StringValue:
			if int64(len(v.Value)) > w.max-int64(w.Len()) {
				w.overflow = true
				return io.ErrShortBuffer
			}
			b, _ := json.Marshal(v.Value)
			_, err := w.Write(b)
			return err
		case JsonValue_NumberValue:
			s := v.Text
			if !json.Valid([]byte(s)) || s == "" || s[0] != '-' && (s[0] < '0' || s[0] > '9') || s[len(s)-1] < '0' || s[len(s)-1] > '9' {
				return io.ErrUnexpectedEOF
			}
			return write(s)
		case JsonValue_ArrayValue:
			if v.Values == nil || activeLists[v.Values] {
				return io.ErrUnexpectedEOF
			}
			activeLists[v.Values] = true
			defer delete(activeLists, v.Values)
			if err := write("["); err != nil {
				return err
			}
			for i, x := range v.Values.Items {
				if i > 0 {
					if err := write(","); err != nil {
						return err
					}
				}
				if err := emit(x); err != nil {
					return err
				}
			}
			return write("]")
		case JsonValue_ObjectValue:
			if v.Values == nil || activeMaps[v.Values] {
				return io.ErrUnexpectedEOF
			}
			activeMaps[v.Values] = true
			defer delete(activeMaps, v.Values)
			if err := write("{"); err != nil {
				return err
			}
			for i, e := range v.Values.Snapshot() {
				if i > 0 {
					if err := write(","); err != nil {
						return err
					}
				}
				key, _ := json.Marshal(e.Key)
				if _, err := w.Write(key); err != nil {
					return err
				}
				if err := write(":"); err != nil {
					return err
				}
				if err := emit(e.Value); err != nil {
					return err
				}
			}
			return write("}")
		}
		return io.ErrUnexpectedEOF
	}
	if err := emit(value); err != nil {
		if w.overflow {
			return Fail[string, JsonError](JsonError_LimitExceeded{})
		}
		return Fail[string, JsonError](JsonError_InvalidData{})
	}
	return Ok[string, JsonError](w.String())
}

// Errors_Message_JsonError returns the fixed JSON diagnostic.
func Errors_Message_JsonError(_ *Execution, e JsonError) string {
	switch e.(type) {
	case JsonError_InvalidInput:
		return dfMessage("JSON", reasonInvalidInput)
	case JsonError_InvalidData:
		return dfMessage("JSON", reasonInvalidData)
	case JsonError_LimitExceeded:
		return dfMessage("JSON", reasonLimitExceeded)
	}
	return dfMessage("JSON", "operation failed")
}
