package nativeabi

// TestEventsEnv is the private result channel between ms and its native test
// executable. Ordinary execution does not set it or write event files.
const TestEventsEnv = "_MANUSCRIPT_TEST_EVENTS"

// TestEvent is an internal append-only protocol. Indices distinguish repeated
// test names without changing declaration/execution order.
type TestEvent struct {
	Event     string   `json:"event"`
	Format    int      `json:"format,omitempty"`
	Available int      `json:"available,omitempty"`
	Names     []string `json:"names,omitempty"`
	Index     int      `json:"index"`
	Failure   string   `json:"failure,omitempty"`
	Reason    string   `json:"reason,omitempty"`
}
