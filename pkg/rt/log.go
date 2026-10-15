package rt

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"strconv"
	"strings"
	"sync"
	"time"
)

var logLevelValues = []LogLevel{LogLevel_Trace{}, LogLevel_Debug{}, LogLevel_Info{}, LogLevel_Warn{}, LogLevel_Error{}, LogLevel_Fatal{}, LogLevel_Silent{}}

// logLevelIndex orders levels from Trace (0) to Silent (6); -1 is not a level.
func logLevelIndex(level LogLevel) int {
	switch level.(type) {
	case LogLevel_Trace:
		return 0
	case LogLevel_Debug:
		return 1
	case LogLevel_Info:
		return 2
	case LogLevel_Warn:
		return 3
	case LogLevel_Error:
		return 4
	case LogLevel_Fatal:
		return 5
	case LogLevel_Silent:
		return 6
	}
	return -1
}

func logFail[T any](e LogError) Result[T, LogError] { return Fail[T, LogError](e) }

// Log_Create builds a logger that writes JSON lines to transport.
func Log_Create(_ *Execution, transport Transport, level Option[LogLevel], bindings Option[*Map[string, JsonValue]], timestamp Option[bool], maxBytes Option[int64]) Result[Logger, LogError] {
	threshold := 2
	if level.Some {
		threshold = logLevelIndex(level.Val)
	}
	max, ok := optionLimit(maxBytes, unlimited)
	if threshold < 0 || !ok {
		return logFail[Logger](LogError_InvalidInput{})
	}
	merged := NewMap[string, JsonValue]()
	if bindings.Some {
		merged = logMerge(bindings.Val)
	}
	stamp := true
	if timestamp.Some {
		stamp = timestamp.Val
	}
	return Ok[Logger, LogError](&jsonLogger{transport: transport, threshold: threshold, bindings: merged, timestamp: stamp, max: max})
}

// Log_StreamTransport writes records to a borrowed stream; closing the
// transport leaves the stream open.
func Log_StreamTransport(_ *Execution, output WriteStream) Transport {
	return newLogTransport(output, nil)
}

// Log_StdoutTransport writes records to standard output.
func Log_StdoutTransport(ctx *Execution) Transport {
	return newLogTransport(hostRoots(ctx).Stdout, nil)
}

// Log_FileTransport appends records to a file the transport owns.
func Log_FileTransport(ctx *Execution, path string) Result[Transport, LogError] {
	opened := hostRoots(ctx).Filesystem.Open(ctx, path, "a", 0600)
	if opened.Failed {
		return logFail[Transport](LogError_FileSystem{Cause: opened.Err})
	}
	handle := opened.Val
	// Delivery and cancellation cleanup belong to the outer acquisition.
	return Ok[Transport, LogError](newLogTransport(handle.Writer(Shield(ctx)), handle))
}

// logMerge copies top-level membership; later maps override earlier values
// without moving the key. Nested JSON data keeps reference semantics.
func logMerge(maps ...*Map[string, JsonValue]) *Map[string, JsonValue] {
	merged := NewMap[string, JsonValue]()
	for _, m := range maps {
		for _, entry := range m.Snapshot() {
			merged.Put(entry.Key, entry.Value)
		}
	}
	return merged
}

type jsonLogger struct {
	mu        sync.Mutex
	transport Transport
	threshold int
	bindings  *Map[string, JsonValue]
	timestamp bool
	max       int64
}

var _ Logger = (*jsonLogger)(nil)

func (l *jsonLogger) Level(*Execution) LogLevel {
	l.mu.Lock()
	defer l.mu.Unlock()
	return logLevelValues[l.threshold]
}

func (l *jsonLogger) SetLevel(_ *Execution, level LogLevel) Unit {
	l.mu.Lock()
	l.threshold = logLevelIndex(level)
	l.mu.Unlock()
	return Unit{}
}

func (l *jsonLogger) Enabled(_ *Execution, level LogLevel) bool {
	l.mu.Lock()
	threshold := l.threshold
	l.mu.Unlock()
	index := logLevelIndex(level)
	return index >= threshold && index >= 0 && index < 6
}

func (l *jsonLogger) Child(_ *Execution, bindings *Map[string, JsonValue]) Logger {
	l.mu.Lock()
	threshold := l.threshold
	l.mu.Unlock()
	return &jsonLogger{transport: l.transport, threshold: threshold, bindings: logMerge(l.bindings, bindings), timestamp: l.timestamp, max: l.max}
}

func (l *jsonLogger) Flush(ctx *Execution) Result[Unit, LogError] { return l.transport.Flush(ctx) }

func (l *jsonLogger) Log(ctx *Execution, level LogLevel, message string, fields Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, logLevelIndex(level), message, fields)
}

func (l *jsonLogger) Trace(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 0, m, f)
}
func (l *jsonLogger) Debug(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 1, m, f)
}
func (l *jsonLogger) Info(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 2, m, f)
}
func (l *jsonLogger) Warn(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 3, m, f)
}
func (l *jsonLogger) Error(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 4, m, f)
}
func (l *jsonLogger) Fatal(ctx *Execution, m string, f Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	return l.emit(ctx, 5, m, f)
}

func (l *jsonLogger) emit(ctx *Execution, level int, message string, fields Option[*Map[string, JsonValue]]) Result[Unit, LogError] {
	l.mu.Lock()
	threshold := l.threshold
	l.mu.Unlock()
	if level < 0 || level >= 6 {
		return logFail[Unit](LogError_InvalidInput{})
	}
	if level < threshold {
		return Ok[Unit, LogError](Unit{})
	}
	metadata := NewMap[string, JsonValue]()
	metadata.Put("level", JsonValue_NumberValue{Text: strconv.Itoa((level + 1) * 10)})
	metadata.Put("msg", JsonValue_StringValue{Value: message})
	extra := NewMap[string, JsonValue]()
	if fields.Some {
		extra = fields.Val
	}
	merged := logMerge(l.bindings, extra)
	// These keys belong to the record envelope even when time is disabled.
	filtered := NewMap[string, JsonValue]()
	for _, entry := range merged.Snapshot() {
		if entry.Key != "level" && entry.Key != "msg" && entry.Key != "time" {
			filtered.Put(entry.Key, entry.Value)
		}
	}
	if l.timestamp {
		metadata.Put("time", JsonValue_NumberValue{Text: strconv.FormatInt(time.Now().UnixMilli(), 10)})
	}
	if l.max == 0 {
		return logFail[Unit](LogError_LimitExceeded{})
	}
	encoded, failure := logEncode(ctx, JsonValue_ObjectValue{Values: logMerge(metadata, filtered)}, l.max-1)
	if failure != nil {
		return logFail[Unit](failure)
	}
	return l.transport.Write(ctx, NewBytes([]byte(encoded+"\n")))
}

// logEncode renders a JSON value as compact text within max bytes. Numbers are
// carried as text and must be valid JSON numbers; cycles are invalid data.
func logEncode(ctx *Execution, value JsonValue, max int64) (string, LogError) {
	var out bytes.Buffer
	overflow := false
	write := func(b []byte) error {
		if int64(len(b)) > max-int64(out.Len()) {
			overflow = true
			return io.ErrShortBuffer
		}
		out.Write(b)
		return nil
	}
	writeString := func(s string) error { return write([]byte(s)) }
	lists := map[*List[JsonValue]]bool{}
	maps := map[*Map[string, JsonValue]]bool{}
	var emit func(JsonValue) error
	emit = func(value JsonValue) error {
		CheckCancelled(ctx)
		switch v := value.(type) {
		case JsonValue_Null:
			return writeString("null")
		case JsonValue_BoolValue:
			return writeString(strconv.FormatBool(v.Value))
		case JsonValue_StringValue:
			if int64(len(v.Value)) > max-int64(out.Len()) {
				overflow = true
				return io.ErrShortBuffer
			}
			b, _ := json.Marshal(v.Value)
			return write(b)
		case JsonValue_NumberValue:
			s := v.Text
			if !json.Valid([]byte(s)) || s == "" || s[0] != '-' && (s[0] < '0' || s[0] > '9') || s[len(s)-1] < '0' || s[len(s)-1] > '9' {
				return io.ErrUnexpectedEOF
			}
			return writeString(s)
		case JsonValue_ArrayValue:
			if lists[v.Values] {
				return io.ErrUnexpectedEOF
			}
			lists[v.Values] = true
			defer delete(lists, v.Values)
			if err := writeString("["); err != nil {
				return err
			}
			for i, x := range v.Values.Items {
				if i > 0 {
					if err := writeString(","); err != nil {
						return err
					}
				}
				if err := emit(x); err != nil {
					return err
				}
			}
			return writeString("]")
		case JsonValue_ObjectValue:
			if maps[v.Values] {
				return io.ErrUnexpectedEOF
			}
			maps[v.Values] = true
			defer delete(maps, v.Values)
			if err := writeString("{"); err != nil {
				return err
			}
			for i, e := range v.Values.Snapshot() {
				if i > 0 {
					if err := writeString(","); err != nil {
						return err
					}
				}
				key, _ := json.Marshal(e.Key)
				if err := write(key); err != nil {
					return err
				}
				if err := writeString(":"); err != nil {
					return err
				}
				if err := emit(e.Value); err != nil {
					return err
				}
			}
			return writeString("}")
		}
		return io.ErrUnexpectedEOF
	}
	if max < 0 {
		return "", LogError_InvalidInput{}
	}
	if err := emit(value); err != nil {
		if overflow {
			return "", LogError_LimitExceeded{}
		}
		return "", LogError_InvalidData{}
	}
	return out.String(), nil
}

// logTransport serializes complete records and cancels admitted operations on
// close. Borrowed streams remain open; file transports own their handle.
type logTransport struct {
	mu       sync.Mutex
	output   WriteStream
	owned    interface{ Close(*Execution) Unit }
	lifetime context.Context
	cancel   context.CancelFunc
	gate     chan struct{}
	closed   bool
	active   sync.WaitGroup
	released chan struct{}
}

var _ Transport = (*logTransport)(nil)

func newLogTransport(output WriteStream, owned interface{ Close(*Execution) Unit }) Transport {
	lifetime, cancel := context.WithCancel(context.Background())
	return &logTransport{output: output, owned: owned, lifetime: lifetime, cancel: cancel, gate: make(chan struct{}, 1), released: make(chan struct{})}
}

func (t *logTransport) Close(ctx *Execution) Unit {
	t.mu.Lock()
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
		t.owned.Close(Shield(ctx))
	}
	t.active.Wait()
	return Unit{}
}

func (t *logTransport) Write(ctx *Execution, data *Bytes) Result[Unit, LogError] {
	return t.operate(ctx, func(inner *Execution) Result[Unit, IoError] { return t.output.Write(inner, data) })
}

func (t *logTransport) Flush(ctx *Execution) Result[Unit, LogError] {
	return t.operate(ctx, func(inner *Execution) Result[Unit, IoError] { return t.output.Flush(inner) })
}

func (t *logTransport) operate(ctx *Execution, do func(*Execution) Result[Unit, IoError]) (result Result[Unit, LogError]) {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return logFail[Unit](LogError_Closed{})
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
				result = logFail[Unit](LogError_Closed{})
			} else {
				panic(failure)
			}
		}
	}()
	select {
	case t.gate <- struct{}{}:
	case <-t.lifetime.Done():
		return logFail[Unit](LogError_Closed{})
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
		return logFail[Unit](LogError_Closed{})
	}
	inner := *ctx
	inner.Context = operationContext
	written := do(&inner)
	if written.Failed {
		return logFail[Unit](LogError_Io{Cause: written.Err})
	}
	return Ok[Unit, LogError](Unit{})
}

var _ = errors.New
var _ = strings.TrimSpace
