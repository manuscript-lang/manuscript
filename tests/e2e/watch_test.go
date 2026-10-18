package e2e_test

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestRunWatchRebuildsAfterEdits(t *testing.T) {
	root := t.TempDir()
	t.Setenv("MANUSCRIPT_CACHE_DIR", filepath.Join(root, "cache"))
	source := filepath.Join(root, "main.ms")
	write := func(code string) {
		t.Helper()
		if err := os.WriteFile(source, []byte(code), 0600); err != nil {
			t.Fatal(err)
		}
	}
	program := func(text string) string {
		return fmt.Sprintf("import stdout from \"@std/io.ms\"\n\nexport fn main() Int:\n    match stdout().write(data: %q.to_bytes()):\n        ok(_):\n            return 0\n        error(_):\n            return 1\n", text+"\n")
	}
	write(program("first"))
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, cliBinary, "run", source, "--watch")
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	command.Stdout, command.Stderr = writer, writer
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	writer.Close()
	lines := make(chan string, 64)
	go func() {
		scanner := bufio.NewScanner(reader)
		for scanner.Scan() {
			lines <- scanner.Text()
		}
		close(lines)
	}()
	var transcript []string
	expect := func(want string) {
		t.Helper()
		for {
			select {
			case line, ok := <-lines:
				if !ok {
					t.Fatalf("watch ended before %q: %q", want, transcript)
				}
				transcript = append(transcript, line)
				if strings.Contains(line, want) {
					return
				}
			case <-ctx.Done():
				t.Fatalf("no %q: %q", want, transcript)
			}
		}
	}
	expect("first")
	expect("waiting for changes")
	write(program("second"))
	expect("restarted run")
	expect("second")
	expect("waiting for changes")
	// A failed edit reports diagnostics and keeps watching.
	write("export fn main() Int:\n    return missing\n")
	expect("missing")
	expect("waiting for changes")
	write(program("third"))
	expect("third")
	expect("waiting for changes")
	if runtime.GOOS == "windows" {
		_ = command.Process.Kill()
	} else {
		_ = command.Process.Signal(os.Interrupt)
	}
	err = command.Wait()
	if exit, ok := err.(*exec.ExitError); runtime.GOOS != "windows" && (!ok || exit.ExitCode() != 130) {
		t.Fatalf("watch exit: %v: %q", err, transcript)
	}
}
