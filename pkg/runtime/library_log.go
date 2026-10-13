package msruntime

import (
	"context"
	"strconv"
	"strings"
	"sync"
	"time"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	result := libraryResult("Unit", "LogError")
	for _, name := range []string{"trace", "debug", "info", "warn", "error", "fatal"} {
		LibraryMethods = append(LibraryMethods, LibraryMethod{"Logger", name, result, []LibraryParam{p("message", "String"), p("fields", "Optional[Map[String][JsonValue]]")}})
	}
	LibraryMethods = append(LibraryMethods,
		LibraryMethod{"Logger", "log", result, []LibraryParam{p("level", "LogLevel"), p("message", "String"), p("fields", "Optional[Map[String][JsonValue]]")}},
		LibraryMethod{"Logger", "enabled", "Bool", []LibraryParam{p("level", "LogLevel")}},
		LibraryMethod{"Logger", "level", "LogLevel", nil},
		LibraryMethod{"Logger", "set_level", "Unit", []LibraryParam{p("level", "LogLevel")}},
		LibraryMethod{"Logger", "child", "Logger", []LibraryParam{p("bindings", "Map[String][JsonValue]")}},
		LibraryMethod{"Logger", "flush", result, nil},
		LibraryMethod{"Transport", "write", result, []LibraryParam{p("data", "Bytes")}},
		LibraryMethod{"Transport", "flush", result, nil},
		LibraryMethod{"Transport", "close", "Unit", nil},
	)
	libraryAdd("log", "create", libraryResult("Logger", "LogError"), []LibraryParam{p("transport", "Transport"), p("level", "Optional[LogLevel]"), p("bindings", "Optional[Map[String][JsonValue]]"), p("timestamp", "Optional[Bool]"), p("max_bytes", "Optional[Int]")}, func(_ *Execution, r string, a []Value) Value {
		level := logLevel(logOption(a[1], Alternative{Type: "@std/LogLevel", Tag: "Info"}))
		if level < 0 || a[4].(int64) < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, ViewOf("@std/Logger", &libraryLogger{transport: a[0], threshold: level, bindings: logMerge(logOption(a[2], &Map{}).(*Map)), timestamp: logOption(a[3], true).(bool), max: a[4].(int64)}))
	})
	libraryAdd("log", "stream_transport", "Transport", []LibraryParam{p("output", "WriteStream")}, func(_ *Execution, _ string, a []Value) Value {
		return newLogTransport(a[0], nil)
	})
	libraryAdd("log", "stdout_transport", "Transport", nil, func(ctx *Execution, _ string, _ []Value) Value {
		return newLogTransport(hostValue(ctx, "stdout"), nil)
	})
	libraryAdd("log", "file_transport", libraryResult("Transport", "LogError"), []LibraryParam{p("path", "String")}, func(ctx *Execution, r string, a []Value) Value {
		opened := Invoke(ctx, Bind(hostValue(ctx, "filesystem"), "", "open"), []Argument{{"path", a[0]}, {"flags", "a"}, {"mode", int64(0600)}}).(Alternative)
		if opened.Tag == "error" {
			return libraryErrorFields(r, "FileSystem", opened.Fields)
		}
		handle := opened.Fields[0]
		// Delivery and cancellation cleanup belong to the outer acquisition.
		output := Invoke(Shield(ctx), Bind(handle, "", "writer"), nil)
		return libraryOK(r, newLogTransport(output, handle))
	})
}

var logLevels = []string{"Trace", "Debug", "Info", "Warn", "Error", "Fatal", "Silent"}

// Optional settings retain their declared values; only absence selects a default.
func logOption(value, fallback Value) Value {
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

func logLevel(value Value) int {
	v := value.(Alternative)
	for i, name := range logLevels {
		if v.Tag == name {
			return i
		}
	}
	return -1
}

// Copy top-level membership; nested JSON data retains ordinary reference semantics.
func logMerge(maps ...*Map) *Map {
	entries := []Entry{}
	positions := map[string]int{}
	for _, m := range maps {
		for _, entry := range m.Entries {
			key := entry.Key.(string)
			if i, ok := positions[key]; ok {
				entries[i] = entry
			} else {
				positions[key] = len(entries)
				entries = append(entries, entry)
			}
		}
	}
	return &Map{Type: "@std/Map[String][@std/JsonValue]", Entries: entries}
}

func logJSON(tag string, value Value) Alternative {
	return Alternative{Type: "@std/JsonValue", Tag: tag, Fields: []Value{value}}
}

type libraryLogger struct {
	mu        sync.Mutex
	transport Value
	threshold int
	bindings  *Map
	timestamp bool
	max       int64
}

func (l *libraryLogger) Operation(name string) Function {
	return libraryMethod("Logger", name, func(ctx *Execution, r string, a []Value) Value {
		l.mu.Lock()
		threshold := l.threshold
		if name == "set_level" {
			l.threshold = logLevel(a[0])
		}
		l.mu.Unlock()
		switch name {
		case "level":
			return Alternative{Type: "@std/LogLevel", Tag: logLevels[threshold]}
		case "set_level":
			return Unit{}
		case "enabled":
			level := logLevel(a[0])
			return level >= threshold && level >= 0 && level < 6
		case "child":
			return ViewOf("@std/Logger", &libraryLogger{transport: l.transport, threshold: threshold, bindings: logMerge(l.bindings, a[0].(*Map)), timestamp: l.timestamp, max: l.max})
		case "flush":
			return Invoke(ctx, Bind(l.transport, "", "flush"), nil)
		}
		level := -1
		if name == "log" {
			level = logLevel(a[0])
			a = a[1:]
		} else {
			for i, tag := range logLevels[:6] {
				if strings.EqualFold(tag, name) {
					level = i
				}
			}
		}
		if level < 0 || level >= 6 {
			return libraryError(r, "InvalidInput", "")
		}
		if level < threshold {
			return libraryOK(r, Unit{})
		}
		metadata := &Map{Entries: []Entry{
			{Key: "level", Value: logJSON("NumberValue", strconv.Itoa((level+1)*10))},
			{Key: "msg", Value: logJSON("StringValue", a[0])},
		}}
		fields := logMerge(l.bindings, logOption(a[1], &Map{}).(*Map))
		// These keys belong to the record envelope even when time is disabled.
		filtered := &Map{}
		for _, entry := range fields.Entries {
			if entry.Key != "level" && entry.Key != "msg" && entry.Key != "time" {
				filtered.Entries = append(filtered.Entries, entry)
			}
		}
		if l.timestamp {
			metadata.Entries = append(metadata.Entries, Entry{Key: "time", Value: logJSON("NumberValue", strconv.FormatInt(time.Now().UnixMilli(), 10))})
		}
		if l.max == 0 {
			return libraryError(r, "LimitExceeded", "")
		}
		encoded := libraryJSONStringify(ctx, libraryRuntimeType(libraryResult("String", "LogError")), []Value{logJSON("ObjectValue", logMerge(metadata, filtered)), l.max - 1}).(Alternative)
		if encoded.Tag == "error" {
			return Alternative{Type: r, Tag: "error", Fields: encoded.Fields}
		}
		return Invoke(ctx, Bind(l.transport, "", "write"), []Argument{{"data", Bytes{Items: []byte(encoded.Fields[0].(string) + "\n")}}})
	})
}

// Transports serialize complete records and cancel admitted operations on close.
// Borrowed streams remain open; file transports own their handle.
type libraryLogTransport struct {
	mu       sync.Mutex
	output   Value
	owned    Value
	lifetime context.Context
	cancel   context.CancelFunc
	gate     chan struct{}
	closed   bool
	active   sync.WaitGroup
	released chan struct{}
}

func newLogTransport(output, owned Value) Value {
	lifetime, cancel := context.WithCancel(context.Background())
	return ViewOf("@std/Transport", &libraryLogTransport{output: output, owned: owned, lifetime: lifetime, cancel: cancel, gate: make(chan struct{}, 1), released: make(chan struct{})})
}

func (t *libraryLogTransport) Operation(name string) Function {
	return libraryMethod("Transport", name, func(ctx *Execution, r string, a []Value) (value Value) {
		t.mu.Lock()
		if name == "close" {
			if t.closed {
				t.mu.Unlock()
				<-t.released
				return Unit{}
			}
			t.closed = true
			t.cancel()
			t.mu.Unlock()
			defer close(t.released)
			if t.owned != nil {
				Invoke(Shield(ctx), Bind(t.owned, "", "close"), nil)
			}
			t.active.Wait()
			return Unit{}
		}
		if t.closed {
			t.mu.Unlock()
			return libraryError(r, "Closed", "")
		}
		t.active.Add(1)
		t.mu.Unlock()
		defer t.active.Done()
		operationContext, cancel := context.WithCancel(ctx.Context)
		stop := context.AfterFunc(t.lifetime, cancel)
		defer func() { stop(); cancel() }()
		defer func() {
			if failure := recover(); failure != nil {
				if _, ok := failure.(cancelled); ok && t.lifetime.Err() != nil {
					CheckCancelled(ctx)
					value = libraryError(r, "Closed", "")
				} else {
					panic(failure)
				}
			}
		}()
		select {
		case t.gate <- struct{}{}:
		case <-t.lifetime.Done():
			return libraryError(r, "Closed", "")
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		}
		defer func() { <-t.gate }()
		// A ready gate can win the select even when close has cancelled the
		// lifetime. Recheck admission before touching the borrowed stream.
		t.mu.Lock()
		closed := t.closed
		t.mu.Unlock()
		if closed {
			return libraryError(r, "Closed", "")
		}
		arguments := []Argument{}
		if name == "write" {
			arguments = append(arguments, Argument{"data", a[0]})
		}
		written := Invoke(inherit(ctx, operationContext), Bind(t.output, "", name), arguments).(Alternative)
		if written.Tag == "error" {
			return libraryErrorFields(r, "Io", written.Fields)
		}
		return libraryOK(r, Unit{})
	})
}
