package nativeabi

import (
	"encoding/json"
	"testing"
)

func BenchmarkReceiverBinding(b *testing.B) {
	for _, operation := range []string{"map", "missing"} {
		b.Run(operation, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				_ = ReceiverBindings["List"][operation]
			}
		})
	}
}

func BenchmarkTestEventJSON(b *testing.B) {
	for _, event := range []TestEvent{
		{Event: "passed", Index: 2, DurationNS: 12345},
		{Event: "plan", Format: 1, Available: 3, Names: []string{"same", "same", "unicode λ"}, Repeat: 2, Seed: 4, Shuffled: true},
	} {
		b.Run(event.Event, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				if _, err := json.Marshal(event); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
