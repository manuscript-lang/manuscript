package build_test

import (
	"bufio"
	"bytes"
	"context"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestNativeProfileExitAndFlush(t *testing.T) {
	for _, mode := range []string{"success", "fault", "cancel"} {
		t.Run(mode, func(t *testing.T) {
			if mode == "cancel" && runtime.GOOS == "windows" {
				t.Skip("os.Interrupt delivery to a child is unavailable on Windows")
			}
			root := t.TempDir()
			source := "export fn main() -> Int:\n    return 7\n"
			expect := 7
			if mode == "fault" {
				source = "import panic from \"@std/faults.ms\"\nexport fn main() -> Int:\n    return panic(message: \"profile failure\")\n"
				expect = 70
			} else if mode == "cancel" {
				source = "import { duration, sleep } from \"@std/time.ms\"\nimport stdout from \"@std/io.ms\"\nexport fn main() -> Int:\n    stdout().write(data: \"ready\\n\".to_bytes())\n    sleep(duration(nanoseconds: 60000000000))\n    return 0\n"
				expect = 130
			}
			cpu, heap, trace := filepath.Join(root, "cpu.pprof"), filepath.Join(root, "heap.pprof"), filepath.Join(root, "trace.out")
			result := compiler.CompileSource("exit.ms", source, compiler.Options{Entry: true, CPUProfile: cpu, HeapProfile: heap, Trace: trace})
			if !result.Success() {
				t.Fatal(result.Diagnostics)
			}
			binary := filepath.Join(root, "program")
			if _, err := build.BuildCheckedWithType(result, binary, compiler.RelWithDebInfo); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			command := exec.CommandContext(ctx, binary)
			var errors bytes.Buffer
			command.Stderr = &errors
			stdout, err := command.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err := command.Start(); err != nil {
				t.Fatal(err)
			}
			if mode == "cancel" {
				ready := make(chan string, 1)
				go func() { line, _ := bufio.NewReader(stdout).ReadString('\n'); ready <- line }()
				select {
				case line := <-ready:
					if line != "ready\n" {
						t.Fatal("cancel target did not reach its source body", line)
					}
				case <-ctx.Done():
					t.Fatal("cancel target did not start", ctx.Err())
				}
				if err := command.Process.Signal(os.Interrupt); err != nil {
					t.Fatal(err)
				}
			}
			_ = command.Wait()
			if command.ProcessState.ExitCode() != expect {
				t.Fatalf("%s: exit %d, want %d: %s", mode, command.ProcessState.ExitCode(), expect, errors.String())
			}
			if mode == "fault" && (!strings.Contains(errors.String(), "profile failure") || !strings.Contains(errors.String(), "exit.ms:3")) {
				t.Fatal("profile lost source fault diagnostics", errors.String())
			}
			for _, viewer := range []struct {
				tool string
				args []string
			}{
				{"pprof", []string{"-top", cpu}},
				{"pprof", []string{"-top", heap}},
				{"trace", []string{"-d=parsed", trace}},
			} {
				command, err := build.ProfileCommand(viewer.tool, viewer.args...)
				if err != nil {
					t.Fatal(err)
				}
				if data, err := command.CombinedOutput(); err != nil {
					t.Fatalf("%s did not flush a valid %s: %v: %s", mode, viewer.tool, err, data)
				}
			}
		})
	}
}
