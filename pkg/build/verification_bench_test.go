package build_test

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/build"
)

// The payload need not be executable: VerifyBuild validates its bytes against
// metadata without launching it. Sizes cover small through debug-size artifacts.
func BenchmarkVerifyBuild(b *testing.B) {
	for _, size := range []int{1 << 10, 1 << 20, 8 << 20, 32 << 20} {
		b.Run(fmt.Sprint(size), func(b *testing.B) {
			path := filepath.Join(b.TempDir(), "program")
			data := make([]byte, size)
			for i := range data {
				data[i] = byte(i * 31)
			}
			if err := os.WriteFile(path, data, 0600); err != nil {
				b.Fatal(err)
			}
			sum := sha256.Sum256(data)
			metadata := build.BuildMetadata{BuildPin: build.BuildPin{Format: 1}, ExecutableSHA256: hex.EncodeToString(sum[:])}
			encoded, err := json.Marshal(metadata)
			if err != nil {
				b.Fatal(err)
			}
			if err := os.WriteFile(path+".ms-build.json", encoded, 0600); err != nil {
				b.Fatal(err)
			}
			b.SetBytes(int64(size))
			b.ReportAllocs()
			b.ResetTimer()
			for range b.N {
				if err := build.VerifyBuild(path, nil); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
