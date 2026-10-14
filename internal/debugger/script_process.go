package debugger

// Script cancellation binds an OS process identity or the owning debugserver
// connection. A cached os.Process can use a recyclable PID and is insufficient.
type scriptProcess interface {
	Interrupt() error
	Reap() error
	Close() error
}
