package cli

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/pkg/build"
	"os"
	"path/filepath"
)

const cacheHelp = `Usage: ms cache clean [directory|ms.toml]

Remove build caches: the project's .ms-cache (the current directory unless
given) and the per-user artifact cache used by standalone run, test, debug,
and profile. Bundled toolchains stay, since running ms commands use them.
Builds also bound each cache to about 128 MiB, evicting least recently used
entries. A standalone ms build keeps its cache in .ms-cache beside the output.

Options:
  -h, --help  Show this help without executing the command

Examples:
  ms cache clean
  ms cache clean path/to/ms.toml
`

func runCache(args []string) int {
	if len(args) == 0 || args[0] != "clean" || len(args) > 2 {
		fmt.Fprintln(os.Stderr, "usage: ms cache clean [directory|ms.toml]; run 'ms help cache' for details")
		return 2
	}
	project := "."
	if len(args) == 2 {
		project = args[1]
	}
	if filepath.Base(project) == "ms.toml" {
		project = filepath.Dir(project)
	}
	dirs := []string{filepath.Join(project, ".ms-cache")}
	if user, err := build.DefaultBuildCacheDir(); err == nil {
		dirs = append(dirs, user)
	}
	var freed int64
	for _, dir := range dirs {
		size, err := build.CleanBuildCache(dir)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		freed += size
	}
	fmt.Printf("Removed %.1f MiB of build cache\n", float64(freed)/(1<<20))
	return 0
}
