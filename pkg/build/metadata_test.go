package build_test

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"os"
	"path/filepath"
	"testing"
)

func TestVerifyBuildRejectsStaleArtifacts(t *testing.T) {
	hash := func(value string) string {
		sum := sha256.Sum256([]byte(value))
		return hex.EncodeToString(sum[:])
	}
	for _, kind := range []string{"valid", "missing metadata", "invalid metadata", "wrong format", "missing executable", "changed executable", "missing source", "changed source", "changed configuration"} {
		t.Run(kind, func(t *testing.T) {
			root := t.TempDir()
			binary := filepath.Join(root, "program")
			metadata := build.BuildMetadata{
				BuildPin:         build.BuildPin{Format: 1},
				Sources:          map[string]string{"main.ms": hash("source"), "ms.toml": hash("configuration")},
				ExecutableSHA256: hash("executable"),
			}
			sources := map[string]string{"main.ms": "source", "ms.toml": "configuration"}
			contents := "executable"
			switch kind {
			case "wrong format":
				metadata.Format = 2
			case "changed executable":
				contents = "different executable"
			case "missing source":
				delete(sources, "main.ms")
			case "changed source":
				sources["main.ms"] = "different source"
			case "changed configuration":
				sources["ms.toml"] = "different configuration"
			}
			if kind != "missing executable" {
				if err := os.WriteFile(binary, []byte(contents), 0600); err != nil {
					t.Fatal(err)
				}
			}
			if kind != "missing metadata" {
				data, err := json.Marshal(metadata)
				if err != nil {
					t.Fatal(err)
				}
				if kind == "invalid metadata" {
					data = []byte("{")
				}
				if err := os.WriteFile(binary+".ms-build.json", data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			err := build.VerifyBuild(binary, sources)
			if (err == nil) != (kind == "valid") {
				t.Fatalf("%s: %v", kind, err)
			}
		})
	}
}
