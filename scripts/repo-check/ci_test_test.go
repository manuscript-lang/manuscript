package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

// Exercise the real POSIX script with a fake SDK, including discovery commands
// that print partial inventories before failing. Each invocation has its own
// record because the script runs test groups concurrently.
const ciMockGo = `#!/bin/sh
set -eu
printf '%s\n' "$@" > "$CI_FIXTURE/calls/call.$$"
case "$1" in
    list)
        case "$2" in
            ./...)
                [ ! -f "$CI_FIXTURE/listed-all" ] || exit 29
                touch "$CI_FIXTURE/listed-all"
                case "$CI_FAILURE" in
                    packages) head -n 1 "$CI_FIXTURE/packages"; exit 23 ;;
                    empty-packages) exit 0 ;;
                esac
                cat "$CI_FIXTURE/packages" ;;
            ./internal/debugger)
                [ "$CI_FAILURE" != race-packages ] || exit 23
                cat "$CI_FIXTURE/race-packages" ;;
            ./pkg/compiler)
                [ "$CI_FAILURE" != split-packages ] || exit 23
                cat "$CI_FIXTURE/split-packages" ;;
            *) exit 25 ;;
        esac ;;
    test)
        case " $* " in
            *' -list '*)
                name=${2##*/}
                if [ "$CI_FAILURE" = "discovery-$name" ]; then
                    echo TestPartial
                    exit 23
                fi
                if [ "$CI_FAILURE" != "empty-$name" ]; then
                    cat "$CI_FIXTURE/tests-$name"
                fi
                printf 'ok\t%s\t0.01s\n' "$2" ;;
            *) [ "$MANUSCRIPT_EXAMPLES_NATIVE" = 1 ] ;;
        esac ;;
    *) exit 25 ;;
esac
`

type ciFixture struct {
	directory   string
	packages    []string
	race        []string
	inventories map[string][]string
}

func newCIFixture(t *testing.T, build bool) ciFixture {
	t.Helper()
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("CI script requires a POSIX shell")
	}
	f := ciFixture{
		directory: filepath.Join(t.TempDir(), "checkout with spaces"),
		packages:  []string{module, module + "/pkg/runtime", module + "/pkg/compiler", module + "/tests/e2e", module + "/pkg/checker", module + "/scripts/repo-check", module + "/tests/examples", module + "/pkg/syntax"},
		race:      []string{module + "/pkg/runtime", module + "/pkg/compiler", module + "/pkg/checker"},
		inventories: map[string][]string{
			module + "/pkg/compiler": {"TestCompileA", "TestCompileB", "TestCompileC", "TestCompileD", "TestCompileE"},
			module + "/tests/e2e":    {"TestNativeA", "TestNativeB", "TestNativeC"},
		},
	}
	if build {
		f.packages = append(f.packages, module+"/pkg/lower", module+"/pkg/build")
		f.race = append(f.race, module+"/pkg/lower", module+"/pkg/build")
		f.inventories[module+"/pkg/build"] = []string{"TestBuildA", "TestBuildB", "TestBuildC", "TestBuildD", "TestBuildE", "TestBuildF"}
		for _, dir := range []string{"pkg/lower", "pkg/build"} {
			if err := os.MkdirAll(filepath.Join(f.directory, dir), 0700); err != nil {
				t.Fatal(err)
			}
		}
	}
	script, err := os.ReadFile("../../scripts/ci-test.sh")
	if err != nil {
		t.Fatal(err)
	}
	f.write(t, "scripts/ci-test.sh", string(script), 0600)
	f.write(t, "toolchain/go/bin/go", ciMockGo, 0700)
	f.write(t, "packages", strings.Join(f.packages, "\n")+"\n", 0600)
	f.write(t, "race-packages", strings.Join(f.race, "\n")+"\n", 0600)
	split := []string{module + "/pkg/compiler", module + "/tests/e2e"}
	if build {
		split = append(split, module+"/pkg/build")
	}
	f.write(t, "split-packages", strings.Join(split, "\n")+"\n", 0600)
	for pkg, tests := range f.inventories {
		f.write(t, "tests-"+filepath.Base(pkg), strings.Join(tests, "\n")+"\n", 0600)
	}
	if err := os.MkdirAll(filepath.Join(f.directory, "calls"), 0700); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f ciFixture) write(t *testing.T, path, data string, mode os.FileMode) {
	t.Helper()
	path = filepath.Join(f.directory, path)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(data), mode); err != nil {
		t.Fatal(err)
	}
}

func (f ciFixture) run(shard int, failure string) ([]byte, error) {
	cmd := exec.Command("sh", filepath.Join(f.directory, "scripts/ci-test.sh"), fmt.Sprint(shard), "4")
	cmd.Env = append(os.Environ(), "CI_FIXTURE="+f.directory, "CI_FAILURE="+failure)
	return cmd.CombinedOutput()
}

func TestCITestDiscoveryFailures(t *testing.T) {
	for _, failure := range []string{"packages", "empty-packages", "race-packages", "split-packages", "discovery-compiler", "discovery-e2e", "discovery-build", "empty-compiler", "empty-e2e", "empty-build"} {
		t.Run(failure, func(t *testing.T) {
			f := newCIFixture(t, true)
			if output, err := f.run(0, failure); err == nil {
				t.Fatalf("discovery failure produced a green shard:\n%s", output)
			}
		})
	}
}

func TestCITestShardInventory(t *testing.T) {
	for _, build := range []bool{false, true} {
		t.Run(fmt.Sprintf("build-package=%v", build), func(t *testing.T) {
			counts := map[string]int{}
			var f ciFixture
			for shard := 0; shard < 4; shard++ {
				f = newCIFixture(t, build)
				if output, err := f.run(shard, ""); err != nil {
					t.Fatalf("shard %d: %v\n%s", shard, err, output)
				}
				entries, err := os.ReadDir(filepath.Join(f.directory, "calls"))
				if err != nil {
					t.Fatal(err)
				}
				listCount := 0
				for _, entry := range entries {
					data, err := os.ReadFile(filepath.Join(f.directory, "calls", entry.Name()))
					if err != nil {
						t.Fatal(err)
					}
					args := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
					if slices.Equal(args, []string{"list", "./..."}) {
						listCount++
					}
					if args[0] != "test" || slices.Contains(args, "-list") {
						continue
					}
					var packages []string
					for _, arg := range args {
						if arg == module || strings.HasPrefix(arg, module+"/") {
							packages = append(packages, arg)
						}
					}
					for _, pkg := range packages {
						race := slices.Contains(f.race, pkg)
						if slices.Contains(args, "-race") != race {
							t.Fatalf("lost race policy for %s: %v", pkg, args)
						}
						if race && slices.Contains(args, "-covermode=atomic") {
							t.Fatalf("race checks must run without coverage: %v", args)
						}
						if !race && (!slices.Contains(args, "-covermode=atomic") || !slices.Contains(args, "-coverpkg="+strings.Join(f.packages, ","))) {
							t.Fatalf("lost complete coverage inventory for %s: %v", pkg, args)
						}
						if pkg == module+"/pkg/runtime" && len(packages) != 1 {
							t.Fatal("runtime race check must run alone", args)
						}
						if tests, split := f.inventories[pkg]; split {
							at := slices.Index(args, "-run")
							if at < 0 || at+1 == len(args) {
								t.Fatal("missing shard test selection", args)
							}
							pattern := regexp.MustCompile(args[at+1])
							for _, name := range tests {
								if pattern.MatchString(name) {
									counts[pkg+"/"+name]++
								}
							}
						} else {
							counts[pkg]++
						}
					}
				}
				if listCount != 1 {
					t.Fatalf("complete package inventory queried %d times", listCount)
				}
			}
			for _, pkg := range f.packages {
				keys := []string{pkg}
				if tests, split := f.inventories[pkg]; split {
					keys = nil
					for _, name := range tests {
						keys = append(keys, pkg+"/"+name)
					}
				}
				for _, key := range keys {
					if counts[key] != 1 {
						t.Fatalf("%s executed %d times across four shards", key, counts[key])
					}
				}
			}
		})
	}
}
