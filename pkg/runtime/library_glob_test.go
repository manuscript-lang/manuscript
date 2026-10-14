package msruntime

import (
	"strings"
	"testing"
	"time"
)

// A run of stars over a long segment must stay linear in the segment length.
func TestGlobStarRunsAreNotQuadratic(t *testing.T) {
	value := strings.Repeat("a", 4000)
	start := time.Now()
	if libraryGlobMatch(value, strings.Repeat("*a", 400)+"b") {
		t.Fatal("pattern ending in b matched a value of only a")
	}
	if !libraryGlobMatch(value, strings.Repeat("*a", 400)) {
		t.Fatal("stars and literals failed to match")
	}
	if elapsed := time.Since(start); elapsed > 20*time.Second {
		t.Fatalf("matching took %s", elapsed)
	}
}

func TestGlobStarMatching(t *testing.T) {
	for _, tt := range []struct {
		value, pattern string
		want           bool
	}{
		{"abc", "*", true},
		{"", "*", true},
		{"abc", "a*c", true},
		{"ac", "a*c", true},
		{"abc", "a*b*c", true},
		{"abc", "*b*", true},
		{"abc", "**c", true},
		{"abc", "a?*", true},
		{"a", "a?*", false},
		{"abc", "*d", false},
		{"abcabc", "*abc*abc", true},
		{"abab", "*ab*ba", false},
		{"é", "?*", true},
	} {
		if got := libraryGlobMatch(tt.value, tt.pattern); got != tt.want {
			t.Errorf("match(%q, %q) = %v, want %v", tt.value, tt.pattern, got, tt.want)
		}
	}
}
