// bench-profile separates fib(29) execution from capture setup/shutdown.
// Prepare with -build-only, then measure without other builds/tests running.
// Use the checkout's pinned Go SDK to run this harness; native builds and
// profile viewers continue to use only Manuscript's embedded toolchain.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

const source = `fn fib(n: Int) -> Int:
    if n < 2:
        return n
    return fib(n: n - 1) + fib(n: n - 2)

export fn main() -> Int:
    return fib(n: 29) % 2
`

func main() {
	output := flag.String("output", "", "directory for prepared binaries and capture files (required)")
	count := flag.Int("count", 3, "repetitions after warmup")
	buildOnly := flag.Bool("build-only", false, "prepare binaries before measuring")
	modes := flag.String("modes", "none,cpu,heap,trace,all,cpuheap", "comma-separated capture modes; restrict expensive legacy traces")
	flag.Parse()
	if *output == "" || *count < 1 {
		fmt.Fprintln(os.Stderr, "provide -output <directory> and a positive -count")
		os.Exit(2)
	}
	root, err := filepath.Abs(*output)
	must(err)
	must(os.MkdirAll(root, 0700))
	for _, mode := range strings.Split(*modes, ",") {
		switch mode {
		case "none", "cpu", "heap", "trace", "all", "cpuheap":
		default:
			panic("unknown capture mode " + mode)
		}
		dir := filepath.Join(root, mode)
		must(os.MkdirAll(dir, 0700))
		binary := filepath.Join(dir, "program")
		if *buildOnly {
			options := compiler.Options{Entry: true}
			if mode == "cpu" || mode == "all" || mode == "cpuheap" {
				options.CPUProfile = filepath.Join(dir, "cpu.pprof")
			}
			if mode == "heap" || mode == "all" || mode == "cpuheap" {
				options.HeapProfile = filepath.Join(dir, "heap.pprof")
			}
			if mode == "trace" || mode == "all" {
				options.Trace = filepath.Join(dir, "trace.out")
			}
			result := compiler.CompileSource("fib.ms", source, options)
			if !result.Success() {
				panic(result.Diagnostics)
			}
			// Time RunMain inside Profile, excluding profile setup/flush and native build.
			result.Source = strings.Replace(result.Source, "import (", "import (\n\"time\"\n\"fmt\"", 1)
			result.Source = strings.ReplaceAll(result.Source, "rt.RunMain(", "timedRunMain(")
			result.Source += `
func timedRunMain(main rt.Value, arguments []string) int {
 start := time.Now()
 exit := rt.RunMain(main, arguments)
 fmt.Printf("body_ns=%d\n", time.Since(start).Nanoseconds())
 return exit
}
`
			must(os.WriteFile(filepath.Join(dir, "generated.go"), []byte(result.Source), 0600))
			_, err = compiler.BuildCheckedWithType(result, binary, filepath.Join(root, "cache"), compiler.RelWithDebInfo)
			must(err)
			fmt.Println("built", mode)
			continue
		}
		for i := 0; i <= *count; i++ {
			for _, file := range []string{"cpu.pprof", "heap.pprof", "trace.out"} {
				err = os.Remove(filepath.Join(dir, file))
				if err != nil && !os.IsNotExist(err) {
					must(err)
				}
			}
			command := exec.Command(binary)
			command.Env = append(os.Environ(), "GOMAXPROCS=1")
			start := time.Now()
			out, err := command.CombinedOutput()
			wall := time.Since(start).Nanoseconds()
			// fib(29) is odd, so the exact issue reproducer exits with 1.
			if command.ProcessState == nil || command.ProcessState.ExitCode() != 1 {
				panic(fmt.Sprintf("%s: unexpected result: %v: %s", mode, err, out))
			}
			body, err := strconv.ParseInt(strings.TrimPrefix(strings.TrimSpace(string(out)), "body_ns="), 10, 64)
			must(err)
			row := map[string]any{"mode": mode, "run": i, "warmup": i == 0, "wall_ns": wall, "body_ns": body, "cpu_ns": command.ProcessState.UserTime().Nanoseconds() + command.ProcessState.SystemTime().Nanoseconds()}
			for _, file := range []string{"cpu.pprof", "heap.pprof", "trace.out"} {
				if info, e := os.Stat(filepath.Join(dir, file)); e == nil {
					row[file+"_bytes"] = info.Size()
				}
			}
			data, e := json.Marshal(row)
			must(e)
			fmt.Println(string(data))
		}
	}
}
func must(err error) {
	if err != nil {
		panic(err)
	}
}
