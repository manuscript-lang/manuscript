package msruntime

import (
	"strings"
	"testing"
)

func TestScalarOffsetCacheMatchesFreshScan(t *testing.T) {
	text := strings.Repeat("aé€😀", 600)
	runes := []rune(text)
	for _, n := range []int{0, 5, 5, 3, 1000, 1001, 2399, 7, 2399} {
		got := stringScalarAt(text, int64(n), "Optional[String]", false)
		want := string(runes[n])
		alt, ok := got.(Alternative)
		if !ok || alt.Tag != "some" || alt.Fields[0] != want {
			t.Fatalf("scalar %d: got %v, want %q", n, got, want)
		}
	}
	if got := stringScalarAt(text, 2400, "Optional[String]", false).(Alternative); got.Tag != "none" {
		t.Fatalf("past the end: %v", got)
	}
}
