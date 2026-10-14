package lower

import (
	"strings"
	"testing"
)

func TestPrimitiveIterableLowersOnce(t *testing.T) {
	r := compileSource("iterable.ms", `fn values(create: fn() -> Int) -> List[Int]: [create(), 2]
fn consume() -> Int:
    var total = 0
    for value in values(fn() -> Int: 1):
        total = total + value
    return total
`)
	if !r.Success() {
		t.Fatal(r.Diagnostics)
	}
	if strings.Count(r.Source, "rt.CaptureListInt(") != 1 {
		t.Fatal("typed iterable route missing", r.Source)
	}
}
