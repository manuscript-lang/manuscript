package msruntime

import (
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type boundedReadFunc func([]byte) (int, error)

func (f boundedReadFunc) Read(p []byte) (int, error) { return f(p) }

func TestReadBoundedLimits(t *testing.T) {
	ctx := RootExecution()
	for _, limit := range []int{0, 1, 63, 32767, 32768, 32769, math.MaxInt} {
		t.Run(fmt.Sprint(limit), func(t *testing.T) {
			size := min(limit, 32769)
			input := strings.Repeat("x", size)
			got, code := readBounded(ctx, strings.NewReader(input), limit)
			if code != "" || string(got) != input {
				t.Fatalf("exact read: len=%d, code=%q", len(got), code)
			}
			if limit == math.MaxInt {
				return
			}
			reader := strings.NewReader(input + "extra")
			got, code = readBounded(ctx, reader, limit)
			if got != nil || code != "LimitExceeded" {
				t.Fatalf("over limit: len=%d, code=%q", len(got), code)
			}
			if consumed := size + len("extra") - reader.Len(); consumed != limit+1 {
				t.Fatalf("read %d bytes, want exactly %d", consumed, limit+1)
			}
		})
	}
}

func TestReadBoundedReaderResults(t *testing.T) {
	ctx := RootExecution()
	for _, tt := range []struct {
		name string
		err  error
		data string
		max  int
		want string
		code string
	}{
		{"empty EOF", io.EOF, "", 0, "", ""},
		{"data with EOF", io.EOF, "abc", 3, "abc", ""},
		{"limit before EOF", io.EOF, "abcd", 3, "", "LimitExceeded"},
		{"read error", errors.New("read failed"), "abc", 3, "", "InvalidData"},
		{"limit before read error", errors.New("read failed"), "abcd", 3, "", "LimitExceeded"},
		{"no progress", nil, "", 3, "", "Failed"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			reader := boundedReadFunc(func(p []byte) (int, error) {
				return copy(p, tt.data), tt.err
			})
			got, code := readBounded(ctx, reader, tt.max)
			if string(got) != tt.want || code != tt.code {
				t.Fatalf("read = %q, %q; want %q, %q", got, code, tt.want, tt.code)
			}
		})
	}
}

func BenchmarkReadBounded(b *testing.B) {
	ctx := RootExecution()
	for _, tt := range []struct {
		name string
		size int
		max  int
	}{
		{"empty", 0, 0},
		{"64B", 64, 64},
		{"1KiB", 1024, 1024},
		{"32KiB-1", 32767, 32767},
		{"32KiB", 32768, 32768},
		{"64KiB", 65536, 65536},
		{"unlimited-64B", 64, math.MaxInt},
	} {
		b.Run(tt.name, func(b *testing.B) {
			input := strings.Repeat("x", tt.size)
			b.ReportAllocs()
			b.SetBytes(int64(tt.size))
			for b.Loop() {
				data, code := readBounded(ctx, strings.NewReader(input), tt.max)
				if len(data) != tt.size || code != "" {
					b.Fatalf("read = %d bytes, %q", len(data), code)
				}
			}
		})
	}
}

func BenchmarkFileSystemSmallBoundedRead(b *testing.B) {
	root := b.TempDir()
	input := strings.Repeat("x", 64)
	if err := os.WriteFile(filepath.Join(root, "small.txt"), []byte(input), 0600); err != nil {
		b.Fatal(err)
	}
	ctx := RootExecution()
	fs := &osFileSystem{directory: root}
	b.ReportAllocs()
	for b.Loop() {
		result := fs.ReadFile(ctx, "small.txt", Some(64))
		if result.Failed || string(result.Val.Data) != input {
			b.Fatal(result)
		}
	}
}
