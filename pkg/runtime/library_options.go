package msruntime

import (
	"context"
	"fmt"
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

// nativeBound unwraps an optional Int that may be negative.
func nativeBound(value Value, fallback Value) Value {
	if value == nil {
		return fallback
	}
	if option, ok := value.(Alternative); ok && strings.HasPrefix(option.Type, "@std/Optional[") {
		if option.Tag == "none" {
			return fallback
		}
		return option.Fields[0]
	}
	return value
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

// Classify declarations once, rather than inspecting generic payload values on
// every call. Keep this in step with the adapters in nativeOptions.
func nativeParamsNeedOptions(params []LibraryParam) bool {
	for _, p := range params {
		switch p.Type {
		case "Optional[Int]", "Optional[Duration]", "Optional[JsonLimits]", "Optional[ArchiveLimits]", "Optional[HtmlLimits]":
			return true
		}
		if nativeOptionRecords[libraryRuntimeType(p.Type)] != nil {
			return true
		}
	}
	return false
}

// optionPlan holds what nativeOptions would derive from a declaration's
// parameter strings on every call: which parameters are optional scalars, and
// their defaults. Declarations with option-record parameters keep the general
// adapter.
type optionPlan struct {
	operation string
	params    []LibraryParam
	scalars   []optionSlot
	records   bool
}

type optionSlot struct {
	index    int
	bound    bool
	fallback Value
}

func planOptions(operation string, params []LibraryParam) *optionPlan {
	plan := &optionPlan{operation: operation, params: params}
	for i, p := range params {
		typ := p.Type
		switch typ {
		case "Optional[Int]", "Optional[Duration]":
			typ = strings.TrimSuffix(strings.TrimPrefix(typ, "Optional["), "]")
			plan.scalars = append(plan.scalars, optionSlot{index: i, bound: p.Name == "max_exclusive", fallback: nativeDefault(p.Name, typ, operation)})
		case "Optional[JsonLimits]", "Optional[ArchiveLimits]", "Optional[HtmlLimits]":
			plan.records = true
		}
		if nativeOptionRecords[libraryRuntimeType(typ)] != nil {
			plan.records = true
		}
	}
	return plan
}

// normalize is nativeOptions for a planned declaration. It copies the
// arguments only when a slot is missing or an optional needs its default.
func (plan *optionPlan) normalize(args []Value) ([]Value, bool) {
	if plan.records {
		return nativeOptions(plan.operation, plan.params, args)
	}
	out := args
	copied := false
	if len(args) < len(plan.params) {
		out = make([]Value, len(plan.params))
		copy(out, args)
		copied = true
	}
	for _, slot := range plan.scalars {
		value := out[slot.index]
		if value != nil {
			if option, ok := value.(Alternative); !ok || !strings.HasPrefix(option.Type, "@std/Optional[") {
				continue
			}
		}
		var normalized Value
		if slot.bound {
			normalized = nativeBound(value, slot.fallback)
		} else {
			var ok bool
			if normalized, ok = nativeOption(value, "", slot.fallback); !ok {
				return nil, false
			}
		}
		if !copied {
			out = append([]Value{}, args...)
			copied = true
		}
		out[slot.index] = normalized
	}
	return out, true
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
			if p.Name == "max_exclusive" {
				// An exclusive upper bound is a value, not a size or budget, so
				// negative bounds are valid.
				out[i] = nativeBound(out[i], nativeDefault(p.Name, typ, operation))
				continue
			}
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
func nativeOptionFailure(result, operation string, params []LibraryParam, args []Value) Value {
	if strings.Contains(result, "Result[") {
		return libraryError(result, "InvalidInput", "")
	}
	// Name the operation and parameter so a limit that came from user input
	// is diagnosable from the fault text alone.
	for i, p := range params {
		if i >= len(args) {
			break
		}
		option, ok := args[i].(Alternative)
		if !ok || option.Tag != "some" || !strings.HasPrefix(option.Type, "@std/Optional[") {
			continue
		}
		switch v := option.Fields[0].(type) {
		case int64:
			if v < 0 {
				return Panic(fmt.Sprintf("%s: %s must be nonnegative, found %d", operation, p.Name, v))
			}
		case Duration:
			if v < 0 {
				return Panic(fmt.Sprintf("%s: %s must be nonnegative, found %d", operation, p.Name, int64(v)))
			}
		}
	}
	return Panic(operation + ": invalid optional limit or timeout; limits and timeouts must be nonnegative")
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
