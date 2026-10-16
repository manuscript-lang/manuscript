package msruntime

import (
	"context"
	"fmt"
	"io"
	"math"
	"sync"
	"time"
)

// netUnlimited is the budget of an omitted optional limit.
const netUnlimited = math.MaxInt

// netNoTimeout is the timeout of an omitted optional deadline.
const netNoTimeout = Duration(-1)

// optLimit resolves an optional nonnegative limit. A supplied negative value
// is invalid.
func optLimit(o Option[int], fallback int) (int, bool) {
	if !o.Some {
		return fallback, true
	}
	return o.Val, o.Val >= 0
}

// optTimeout resolves an optional nonnegative deadline; none means no deadline.
func optTimeout(o Option[Duration]) (Duration, bool) {
	if !o.Some {
		return netNoTimeout, true
	}
	return o.Val, o.Val >= 0
}

func timeoutContext(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	if timeout < 0 {
		return context.WithCancel(parent)
	}
	return context.WithTimeout(parent, timeout)
}

func transportTimeout(timeout Duration) time.Duration {
	if timeout < 0 {
		return 0
	}
	return time.Duration(timeout)
}

// headerBytesLimit saturates before net/http adds its 4 KiB framing allowance.
func headerBytesLimit(limit int) int {
	largest := int(^uint(0)>>1) - 4096
	if limit > largest {
		limit = largest
	}
	return int(limit)
}

// netChild returns an execution for work that runs beside parent under c.
func netChild(parent *Execution, c context.Context) *Execution {
	return &Execution{Context: c, State: parent.State, calls: &callState{}}
}

// scope is an execution limited by an operation timeout. Cancellation of the
// parent unwinds the task; expiry of the timeout is an expected failure.
type scope struct {
	parent, exec *Execution
	cancel       context.CancelFunc
}

func newScope(ctx *Execution, timeout Duration) scope {
	local, cancel := timeoutContext(ctx.Context, time.Duration(timeout))
	c := *ctx
	c.Context = local
	return scope{parent: ctx, exec: &c, cancel: cancel}
}

// timedOut unwinds when the parent was cancelled and otherwise reports
// whether the operation's own deadline passed.
func (s scope) timedOut() bool {
	CheckCancelled(s.parent)
	return s.exec.Context.Err() != nil
}

// gate admits one operation at a time.
type gate chan struct{}

func newGate() gate {
	g := make(gate, 1)
	g <- struct{}{}
	return g
}

// acquire waits for the gate; it reports false when ctx ends first.
func (g gate) acquire(ctx *Execution) bool {
	select {
	case <-g:
		return true
	case <-ctx.Context.Done():
		return false
	}
}

// mustAcquire waits for the gate and unwinds on cancellation.
func (g gate) mustAcquire(ctx *Execution) {
	if !g.acquire(ctx) {
		CheckCancelled(ctx)
	}
}

func (g gate) release() { g <- struct{}{} }

// lifecycle implements the close protocol of a resource: the first close
// interrupts and joins admitted operations, later closes wait for it.
type lifecycle struct {
	mu       sync.Mutex
	closed   bool
	active   sync.WaitGroup
	released chan struct{}
}

func newLifecycle() lifecycle { return lifecycle{released: make(chan struct{})} }

// enter admits an operation; it reports false once the resource is closed.
func (l *lifecycle) enter() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed {
		return false
	}
	l.active.Add(1)
	return true
}

func (l *lifecycle) leave() { l.active.Done() }

func (l *lifecycle) isClosed() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.closed
}

// begin marks the resource closed. It reports true for the first caller; any
// other caller waits for the first to finish and gets false.
func (l *lifecycle) begin() bool {
	l.mu.Lock()
	if l.closed {
		done := l.released
		l.mu.Unlock()
		<-done
		return false
	}
	l.closed = true
	l.mu.Unlock()
	return true
}

// finish joins admitted operations and releases waiting closers.
func (l *lifecycle) finish() {
	l.active.Wait()
	close(l.released)
}

// interruptWith runs interrupt when ctx ends; stop disarms it and waits for a
// started interrupt.
func interruptWith(ctx *Execution, interrupt func()) func() {
	done := make(chan struct{})
	stop := context.AfterFunc(ctx.Context, func() { defer close(done); interrupt() })
	return func() {
		if !stop() {
			<-done
		}
	}
}

// netInterruptDeadline expires an I/O deadline when ctx ends; stop also clears it.
func netInterruptDeadline(ctx *Execution, deadline func(time.Time) error) func() {
	stop := interruptWith(ctx, func() { deadline(time.Now()) })
	return func() {
		stop()
		deadline(time.Time{})
	}
}

// joinFaults folds failures recovered from cleanup into one fault.
func joinFaults(failures []any) any {
	var pending any
	for _, failure := range failures {
		if primary, ok := pending.(Fault); ok {
			primary.Secondary = append(primary.Secondary, fmt.Sprint(failure))
			pending = primary
		} else if f, ok := failure.(Fault); ok {
			pending = f
		} else {
			pending = Fault{Message: fmt.Sprint(failure)}
		}
	}
	return pending
}

// netReadBounded reads reader to EOF within max bytes. The code names the
// failure: LimitExceeded, InvalidData for a read error, Failed for no progress.
func netReadBounded(ctx *Execution, reader io.Reader, max int) ([]byte, string) {
	var out []byte
	buffer := make([]byte, 32768)
	for {
		CheckCancelled(ctx)
		remaining := max - len(out)
		chunk := buffer
		if remaining < len(buffer) {
			chunk = buffer[:int(remaining)+1]
		}
		n, err := reader.Read(chunk)
		if int(n) > remaining {
			return nil, "LimitExceeded"
		}
		out = append(out, chunk[:n]...)
		if err == io.EOF {
			return out, ""
		}
		if err != nil {
			return nil, "InvalidData"
		}
		if n == 0 {
			return nil, "Failed"
		}
	}
}

// Diagnostic messages carry no input values: URLs, data, and host arguments
// can contain secrets. Only an explicit Failed text is returned verbatim.
const (
	netReasonInvalidInput = "invalid input"
	netReasonInvalidData  = "invalid data"
	reasonLimit           = "limit exceeded"
	reasonDenied          = "permission denied"
	netReasonUnsupported  = "operation not supported"
	reasonClosed          = "resource is closed"
	reasonTimeout         = "operation timed out"
	reasonAuthenticated   = "authentication failed"
	reasonOperation       = "operation failed"
)

func domainMessage(domain, reason string) string { return domain + ": " + reason }

// Errors_Message_NetworkError returns the Failed text verbatim, and otherwise
// the fixed diagnostic `network: <reason>`.
func Errors_Message_NetworkError(_ *Execution, e NetworkError) string {
	switch e := e.(type) {
	case NetworkError_Failed:
		return e.Message
	case NetworkError_InvalidInput:
		return domainMessage("network", netReasonInvalidInput)
	case NetworkError_InvalidData:
		return domainMessage("network", netReasonInvalidData)
	case NetworkError_LimitExceeded:
		return domainMessage("network", reasonLimit)
	case NetworkError_PermissionDenied:
		return domainMessage("network", reasonDenied)
	case NetworkError_Unsupported:
		return domainMessage("network", netReasonUnsupported)
	case NetworkError_Closed:
		return domainMessage("network", reasonClosed)
	case NetworkError_Timeout:
		return domainMessage("network", reasonTimeout)
	}
	return domainMessage("network", reasonOperation)
}

// Errors_Message_HttpError returns the Failed text verbatim, and otherwise the
// fixed diagnostic `HTTP: <reason>`.
func Errors_Message_HttpError(_ *Execution, e HttpError) string {
	switch e := e.(type) {
	case HttpError_Failed:
		return e.Message
	case HttpError_InvalidInput:
		return domainMessage("HTTP", netReasonInvalidInput)
	case HttpError_InvalidData:
		return domainMessage("HTTP", netReasonInvalidData)
	case HttpError_LimitExceeded:
		return domainMessage("HTTP", reasonLimit)
	case HttpError_PermissionDenied:
		return domainMessage("HTTP", reasonDenied)
	case HttpError_Closed:
		return domainMessage("HTTP", reasonClosed)
	case HttpError_Timeout:
		return domainMessage("HTTP", reasonTimeout)
	}
	return domainMessage("HTTP", reasonOperation)
}

// Errors_Message_WebSocketError returns the Failed text verbatim, and
// otherwise the fixed diagnostic `WebSocket: <reason>`.
func Errors_Message_WebSocketError(_ *Execution, e WebSocketError) string {
	switch e := e.(type) {
	case WebSocketError_Failed:
		return e.Message
	case WebSocketError_InvalidInput:
		return domainMessage("WebSocket", netReasonInvalidInput)
	case WebSocketError_InvalidData:
		return domainMessage("WebSocket", netReasonInvalidData)
	case WebSocketError_LimitExceeded:
		return domainMessage("WebSocket", reasonLimit)
	case WebSocketError_PermissionDenied:
		return domainMessage("WebSocket", reasonDenied)
	case WebSocketError_Closed:
		return domainMessage("WebSocket", reasonClosed)
	case WebSocketError_Timeout:
		return domainMessage("WebSocket", reasonTimeout)
	}
	return domainMessage("WebSocket", reasonOperation)
}

// Errors_Message_TlsError returns the fixed diagnostic `TLS: <reason>`
// without echoing certificate text.
func Errors_Message_TlsError(_ *Execution, e TlsError) string {
	switch e.(type) {
	case TlsError_InvalidInput:
		return domainMessage("TLS", netReasonInvalidInput)
	case TlsError_InvalidData:
		return domainMessage("TLS", netReasonInvalidData)
	case TlsError_LimitExceeded:
		return domainMessage("TLS", reasonLimit)
	case TlsError_AuthenticationFailed:
		return domainMessage("TLS", reasonAuthenticated)
	}
	return domainMessage("TLS", reasonOperation)
}

// Errors_Message_UrlError returns a URL-prefixed diagnostic that never echoes
// addresses, query values or credentials.
func Errors_Message_UrlError(_ *Execution, e UrlError) string {
	switch e.(type) {
	case UrlError_InvalidInput:
		return domainMessage("URL", netReasonInvalidInput)
	case UrlError_InvalidData:
		return domainMessage("URL", netReasonInvalidData)
	case UrlError_LimitExceeded:
		return domainMessage("URL", reasonLimit)
	}
	return domainMessage("URL", reasonOperation)
}

func netFail[T any](e NetworkError) Result[T, NetworkError]    { return Fail[T, NetworkError](e) }
func ioFail[T any](e IoError) Result[T, IoError]               { return Fail[T, IoError](e) }
func httpFail[T any](e HttpError) Result[T, HttpError]         { return Fail[T, HttpError](e) }
func wsFail[T any](e WebSocketError) Result[T, WebSocketError] { return Fail[T, WebSocketError](e) }

var (
	errNetInvalidInput  NetworkError = NetworkError_InvalidInput{}
	errNetInvalidData   NetworkError = NetworkError_InvalidData{}
	errNetClosed        NetworkError = NetworkError_Closed{}
	errNetTimeout       NetworkError = NetworkError_Timeout{}
	errNetDenied        NetworkError = NetworkError_PermissionDenied{}
	errNetLimit         NetworkError = NetworkError_LimitExceeded{}
	errNetUnsupported   NetworkError = NetworkError_Unsupported{}
	errIoClosed         IoError      = IoError_Closed{}
	errIoInvalidInput   IoError      = IoError_InvalidInput{}
	errHTTPInvalidInput HttpError    = HttpError_InvalidInput{}
	errHTTPInvalidData  HttpError    = HttpError_InvalidData{}
	errHTTPClosed       HttpError    = HttpError_Closed{}
	errHTTPLimit        HttpError    = HttpError_LimitExceeded{}
	errHTTPDenied       HttpError    = HttpError_PermissionDenied{}
	errHTTPTimeout      HttpError    = HttpError_Timeout{}
)

func netFailed(message string) NetworkError { return NetworkError_Failed{Message: message} }
func ioFailed(message string) IoError       { return IoError_Failed{Message: message} }
func httpFailed(message string) HttpError   { return HttpError_Failed{Message: message} }

func stringItems(l *List[string]) []string {
	if l == nil {
		return nil
	}
	return l.Items
}
