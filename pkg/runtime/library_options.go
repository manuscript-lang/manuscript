package msruntime

import (
	"context"
	"strings"
	"time"
)

const nativeUnlimited = int64(^uint64(0) >> 1)
const nativeNoTimeout = Duration(-1)

func nativeOption(value Value, typ string, fallback Value) (Value, bool) {
	if value == nil {
		return fallback, true
	}
	if option, ok := value.(Alternative); ok && strings.HasPrefix(option.Type, "@std/Optional[") {
		if option.Tag == "none" {
			return fallback, true
		}
		value = option.Fields[0]
		switch v := value.(type) {
		case int64:
			if v < 0 {
				return nil, false
			}
		case Duration:
			if v < 0 {
				return nil, false
			}
		}
	}
	return value, true
}

func nativeDefault(name, typ, operation string) Value {
	switch typ {
	case "Int":
		if name == "max_replacements" {
			return int64(1)
		}
		// A single read requests a chunk, not a whole stream or a total budget.
		if name == "max_bytes" && operation == "receive" {
			return int64(65535)
		}
		if name == "max_bytes" && (operation == "read" || operation == "read_at") {
			return int64(65536)
		}
		if name == "max_events" || name == "capacity" {
			return int64(128)
		}
		return nativeUnlimited
	case "Duration":
		return nativeNoTimeout
	case "JsonLimits", "ArchiveLimits", "HtmlLimits":
		return Record{Type: "@std/" + typ, Fields: map[string]Value{}}
	}
	return nil
}

func nativeOptions(operation string, params []LibraryParam, args []Value) ([]Value, bool) {
	out := append([]Value{}, args...)
	for len(out) < len(params) {
		out = append(out, nil)
	}
	for i, p := range params {
		typ := p.Type
		if typ == "Optional[Int]" || typ == "Optional[Duration]" || typ == "Optional[JsonLimits]" || typ == "Optional[ArchiveLimits]" || typ == "Optional[HtmlLimits]" {
			typ = strings.TrimSuffix(strings.TrimPrefix(typ, "Optional["), "]")
			var ok bool
			out[i], ok = nativeOption(out[i], typ, nativeDefault(p.Name, typ, operation))
			if !ok {
				return nil, false
			}
		}
		// Only declared option-record parameters are adapters. Generic payloads
		// retain their fields and identity, even when they contain option records.
		if record, ok := out[i].(Record); ok && record.Type == libraryRuntimeType(typ) {
			fields := nativeOptionRecords[record.Type]
			if fields == nil {
				continue
			}
			copy := map[string]Value{}
			for name, value := range record.Fields {
				copy[name] = value
			}
			for name, fieldType := range fields {
				if fieldType != "Int" && fieldType != "Duration" {
					continue
				}
				value, valid := nativeOption(copy[name], fieldType, nativeDefault(name, fieldType, operation))
				if !valid {
					return nil, false
				}
				copy[name] = value
			}
			out[i] = Record{Type: record.Type, Fields: copy}
		}
	}
	return out, true
}
func nativeOptionFailure(result string) Value {
	if strings.Contains(result, "Result[") {
		return libraryError(result, "InvalidInput", "")
	}
	return Panic("invalid optional limit or timeout")
}
func nativeContextTimeout(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	if timeout < 0 {
		return context.WithCancel(parent)
	}
	return context.WithTimeout(parent, timeout)
}

func nativeStreamReadSize(value Value) int64 {
	normalized, ok := nativeOption(value, "Int", int64(65536))
	if !ok {
		return -1
	}
	return normalized.(int64)
}

func nativeTransportTimeout(timeout Duration) time.Duration {
	if timeout < 0 {
		return 0
	}
	return time.Duration(timeout)
}

// net/http adds a 4 KiB framing allowance to MaxHeaderBytes. Saturate before
// that addition so an omitted cap cannot overflow into a negative read limit.
func nativeHTTPHeaderBytes(limit int64) int {
	largest := int64(^uint(0)>>1) - 4096
	if limit > largest {
		limit = largest
	}
	return int(limit)
}
