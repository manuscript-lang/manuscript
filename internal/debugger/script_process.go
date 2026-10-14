package debugger

// Script cancellation must refer to a retained OS process identity. A cached
// os.Process can still use a recyclable PID, so it is not this contract.
type scriptProcess interface {
	Kill() error
	Reap()
	Close() error
}
