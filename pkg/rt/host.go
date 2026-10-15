package rt

// HostRoots are the program's capabilities to the host: standard streams,
// arguments, environment, and service handles. The host module defines them.
type HostRoots struct {
	// Network is the root network service; nil until the host wires one, in
	// which case Net_Network creates an OS-backed network on first use.
	Network Network
}
