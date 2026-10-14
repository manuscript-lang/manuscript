package msruntime

import (
	"math/rand"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func naiveScalarOffset(text string, n int) int {
	offset := 0
	for ; n > 0; n-- {
		_, width := utf8.DecodeRuneInString(text[offset:])
		offset += width
	}
	return offset
}

// mixedText returns long text with scalars of every UTF-8 width.
func mixedText(n int) string {
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteRune([]rune{'a', 'é', '€', '🙂'}[i%4])
	}
	return b.String()
}

func TestScalarIndexOffsetMatchesAScanInAnyAccessOrder(t *testing.T) {
	text := mixedText(5000)
	count, ascii := stringShape(text)
	if count != 5000 || ascii {
		t.Fatalf("shape = %d, %v", count, ascii)
	}
	rng := rand.New(rand.NewSource(3))
	positions := []int{0, 4999, 5000, 1, 2500, 2499, 2501, 10, 4000, 3999, 0}
	for i := 0; i < 2000; i++ {
		positions = append(positions, rng.Intn(5001))
	}
	for _, n := range positions {
		if got, want := scalarIndexOffset(text, n), naiveScalarOffset(text, n); got != want {
			t.Fatalf("scalarIndexOffset(%d) = %d, want %d", n, got, want)
		}
	}
	// Another long string must not reuse the first one's cached position.
	other := strings.Repeat("🙂", 3000)
	if got, want := scalarIndexOffset(other, 2999), naiveScalarOffset(other, 2999); got != want {
		t.Fatalf("other text: %d, want %d", got, want)
	}
	if got, want := scalarIndexOffset(text, 4999), naiveScalarOffset(text, 4999); got != want {
		t.Fatalf("after other text: %d, want %d", got, want)
	}
}

func TestStringShapeCacheDistinguishesTexts(t *testing.T) {
	ascii := strings.Repeat("a", 2000)
	wide := strings.Repeat("é", 1000) // same byte length, different scalar count
	if count, isASCII := stringShape(ascii); count != 2000 || !isASCII {
		t.Fatalf("ascii shape = %d, %v", count, isASCII)
	}
	if count, isASCII := stringShape(wide); count != 1000 || isASCII {
		t.Fatalf("wide shape = %d, %v", count, isASCII)
	}
	if count, isASCII := stringShape(ascii); count != 2000 || !isASCII {
		t.Fatalf("ascii shape after wide = %d, %v", count, isASCII)
	}
}

// A lexer-style loop indexing every scalar rescanned the whole text per call
// (ASCII check, scalar count, offset walk), so 400,000 scalars took minutes.
func TestIndexingEveryScalarIsNotQuadratic(t *testing.T) {
	for _, text := range []string{strings.Repeat("abcdefgh", 50000), mixedText(400000)} {
		start := time.Now()
		runes := []rune(text)
		forward, backward := int64(0), int64(0)
		for i := range runes {
			forward += stringScalarAt(text, int64(i), "Optional[Int]", true).(Alternative).Fields[0].(int64)
		}
		for i := len(runes) - 1; i >= 0; i-- {
			backward += stringScalarAt(text, int64(i), "Optional[Int]", true).(Alternative).Fields[0].(int64)
		}
		var want int64
		for _, r := range runes {
			want += int64(r)
		}
		if forward != want || backward != want {
			t.Fatalf("sums %d and %d, want %d", forward, backward, want)
		}
		if elapsed := time.Since(start); elapsed > 5*time.Second {
			t.Fatalf("indexing %d scalars took %v", len(runes), elapsed)
		}
	}
}
