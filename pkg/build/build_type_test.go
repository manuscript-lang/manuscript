package build_test

import (
	"debug/buildinfo"
	"debug/elf"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestBuildTypes(t *testing.T) {
	for name, want := range map[string]compiler.BuildType{
		"": compiler.Release, "debug": compiler.Debug, "Release": compiler.Release,
		"RELWITHDEBINFO": compiler.RelWithDebInfo, "minsizerel": compiler.MinSizeRel,
	} {
		got, err := compiler.ParseBuildType(name)
		if err != nil || got != want {
			t.Fatalf("%q: %q, %v", name, got, err)
		}
	}
	if _, err := compiler.ParseBuildType("Fast"); err == nil {
		t.Fatal("accepted unknown build type")
	}
	result := compiler.CompileSource("main.ms", "export fn main() -> Int:\n    return 0\n", compiler.Options{Entry: true})
	if _, err := build.BuildCheckedWithType(result, filepath.Join(t.TempDir(), "program"), "Fast"); err == nil {
		t.Fatal("build accepted unknown build type")
	}
}

func TestNativeBuildTypes(t *testing.T) {
	root := t.TempDir()
	filename := filepath.Join(root, "main.ms")
	if err := os.WriteFile(filename, []byte("export fn main() -> Int:\n    return 0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	result := compiler.CompileFile(filename, compiler.Options{Entry: true})
	if !result.Success() {
		t.Fatal(result.Diagnostics)
	}
	identities := map[string]bool{}
	sizes := map[compiler.BuildType]int64{}
	for _, kind := range []compiler.BuildType{compiler.Debug, compiler.Release, compiler.RelWithDebInfo, compiler.MinSizeRel} {
		t.Run(string(kind), func(t *testing.T) {
			binary := filepath.Join(root, string(kind))
			metadata, err := build.BuildCheckedWithType(result, binary, kind)
			if err != nil {
				t.Fatal(err)
			}
			if metadata.BuildType != kind || metadata.Debug != (kind == compiler.Debug) || identities[metadata.BuildID] {
				t.Fatal("build type missing or identity reused", metadata)
			}
			identities[metadata.BuildID] = true
			withSymbols := kind == compiler.Debug || kind == compiler.RelWithDebInfo
			if withSymbols && metadata.SourceRoot != root || !withSymbols && metadata.SourceRoot != "" {
				t.Fatal("incorrect source root", metadata)
			}
			if data, err := exec.Command(binary).CombinedOutput(); err != nil {
				t.Fatalf("native execution: %v: %s", err, data)
			}
			built, err := buildinfo.ReadFile(binary)
			if err != nil {
				t.Fatal(err)
			}
			settings := map[string]string{}
			for _, setting := range built.Settings {
				settings[setting.Key] = setting.Value
			}
			if (settings["-gcflags"] == "all=-N -l") != (kind == compiler.Debug) ||
				(settings["-trimpath"] == "true") != !withSymbols {
				t.Fatal("incorrect native optimization settings", settings)
			}
			if runtime.GOOS == "linux" {
				file, err := elf.Open(binary)
				if err != nil {
					t.Fatal(err)
				}
				defer file.Close()
				if (file.Section(".debug_info") != nil) != withSymbols || (file.Section(".symtab") != nil) != withSymbols {
					t.Fatal("incorrect native debug sections")
				}
			}
			info, err := os.Stat(binary)
			if err != nil {
				t.Fatal(err)
			}
			sizes[kind] = info.Size()
			if err := build.VerifyBuild(binary, map[string]string{"main.ms": result.Program.Modules[0].Source}); err != nil {
				t.Fatal(err)
			}
		})
	}
	if len(sizes) == 4 && (sizes[compiler.Release] >= sizes[compiler.RelWithDebInfo] || sizes[compiler.MinSizeRel] >= sizes[compiler.RelWithDebInfo]) {
		t.Fatal("stripping did not reduce executable size", sizes)
	}
	t.Logf("binary sizes: %v", sizes)
}
