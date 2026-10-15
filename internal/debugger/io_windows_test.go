package debugger

import (
	"errors"
	"os"
	"testing"
)

func TestScriptRedirectKeepsBorrowedStderrOpen(t *testing.T) {
	for _, consumed := range []bool{false, true} {
		t.Run(map[bool]string{false: "launch-fails", true: "launch-consumes"}[consumed], func(t *testing.T) {
			borrowed, err := os.CreateTemp(t.TempDir(), "stderr")
			if err != nil {
				t.Fatal(err)
			}
			original := os.Stderr
			os.Stderr = borrowed
			defer func() { os.Stderr = original; _ = borrowed.Close() }()
			var outputs []struct {
				file    *os.File
				cleanup func() error
			}
			for range 2 {
				redirect, cleanup, err := redirectToStderr()
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() {
					if err := cleanup(); err != nil {
						t.Error(err)
					}
				})
				if redirect.File == nil || redirect.File == borrowed {
					t.Fatal("target redirect borrowed stderr")
				}
				outputs = append(outputs, struct {
					file    *os.File
					cleanup func() error
				}{redirect.File, cleanup})
			}
			if outputs[0].file == outputs[1].file {
				t.Fatal("target streams share an owned redirect")
			}
			for _, output := range outputs {
				if consumed {
					if err := output.file.Close(); err != nil {
						t.Fatal(err)
					}
				}
				if err := output.cleanup(); err != nil {
					t.Fatal(err)
				}
				if _, err := output.file.Stat(); !errors.Is(err, os.ErrClosed) {
					t.Fatalf("unused redirect survived cleanup: %v", err)
				}
			}
			if _, err := borrowed.WriteString("borrowed stderr still open"); err != nil {
				t.Fatal(err)
			}
		})
	}
}
