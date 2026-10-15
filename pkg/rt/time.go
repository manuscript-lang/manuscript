package rt

// Duration is a signed count of nanoseconds.
type Duration int64

// ClockDomain identifies the monotonic clock an Instant was read from, so
// instants of different clocks do not compare.
type ClockDomain struct{ identity byte }

// Instant is a monotonic clock reading.
type Instant struct {
	Domain *ClockDomain
	Tick   int64
}

// Timestamp is a wall-clock time: seconds since the Unix epoch and a
// nanosecond component in 0..999999999.
type Timestamp struct {
	Seconds int64
	Nanos   int32
}
