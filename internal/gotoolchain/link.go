package gotoolchain

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"sort"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
)

// link writes Output from every loaded archive.
func (b *builder) link(root *pkg) error {
	work, err := os.MkdirTemp(filepath.Dir(b.Output), ".manuscript-link-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)
	var config strings.Builder
	config.WriteString("# import config\n")
	for _, p := range b.order {
		if p != root {
			fmt.Fprintf(&config, "packagefile %s=%s\n", p.path, p.archive)
		}
	}
	fmt.Fprintf(&config, "modinfo %q\n", b.modinfo())
	importcfg := filepath.Join(work, "importcfg.link")
	if err := os.WriteFile(importcfg, []byte(config.String()), 0644); err != nil {
		return err
	}
	output := filepath.Join(work, "a.out")
	arguments := append([]string{"-o", output, "-importcfg", importcfg, "-buildmode=exe"}, strings.Fields(b.LDFlags)...)
	if err := run("link", b.Dir, b.toolEnvironment(), append(arguments, root.archive)...); err != nil {
		return err
	}
	return os.Rename(output, b.Output)
}

// modinfo is the build information the go command records, readable with
// debug/buildinfo. Settings follow load.(*Package).setBuildInfo.
func (b *builder) modinfo() string {
	info := debug.BuildInfo{Path: b.ImportPath, Main: debug.Module{Path: b.ModulePath, Version: "(devel)"}}
	seen := map[*vendoredModule]bool{}
	for _, p := range b.order {
		if p.module != nil && !seen[p.module] {
			seen[p.module] = true
			info.Deps = append(info.Deps, &debug.Module{Path: p.module.path, Version: p.module.version})
		}
	}
	sort.Slice(info.Deps, func(i, j int) bool { return info.Deps[i].Path < info.Deps[j].Path })
	setting := func(key, value string) {
		info.Settings = append(info.Settings, debug.BuildSetting{Key: key, Value: value})
	}
	setting("-buildmode", "exe")
	setting("-compiler", "gc")
	if b.GCFlags != "" {
		setting("-gcflags", b.GCFlags)
	}
	// Linker flags may name host paths, so trimmed builds omit them.
	if b.LDFlags != "" && !b.Trimpath {
		setting("-ldflags", b.LDFlags)
	}
	if len(b.Tags) > 0 {
		setting("-tags", strings.Join(b.Tags, ","))
	}
	if b.Trimpath {
		setting("-trimpath", "true")
	}
	setting("CGO_ENABLED", "0")
	setting("GOARCH", buildcfg.GOARCH)
	setting("GOOS", buildcfg.GOOS)
	if name, value := buildcfg.GOGOARCH(); name != "" {
		setting(name, value)
	}
	// Markers the runtime uses to find the information (cmd/go/internal/modload).
	const start, end = "0w\xaf\f\x92t\b\x02A\xe1\xc1\a\xe6\xd6\x18\xe6", "\xf92C1\x86\x18 r\x00\x82B\x10A\x16\xd8\xf2"
	return start + info.String() + end
}
