package e2e_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRecursiveTypesRejectUnsafeConstructionAndHashing(t *testing.T) {
	for _, tt := range []struct{ source, want string }{
		{"type Node:\n    next: Optional[Node]\nexport fn main() -> Int:\n    let node = Node(node)\n    return 0\n", "unknown binding node"},
		{"type Node:\n    next: Optional[Node]\nexport fn main() -> Int:\n    let node = Node(none)\n    node.next = some(node)\n    return node.hash()\n", "unknown or ambiguous member hash"},
		{"import List from \"@std/collections.ms\"\ntype Grow[T]:\n    next: fn() -> Grow[List[T]]\nexport fn main() -> Int: return 0\n", "recursive generic applications"},
	} {
		dir := t.TempDir()
		file := filepath.Join(dir, "recursive.ms")
		if err := os.WriteFile(file, []byte(tt.source), 0600); err != nil {
			t.Fatal(err)
		}
		output := filepath.Join(dir, "recursive")
		data, err := commandOutput(t, cliBinary, "build", file, "-o", output)
		if err == nil || !strings.Contains(string(data), tt.want) {
			t.Fatalf("want %s, got %v: %s", tt.want, err, data)
		}
		if _, err := os.Stat(output); !os.IsNotExist(err) {
			t.Fatalf("invalid recursive source produced a binary: %v", err)
		}
	}
}
