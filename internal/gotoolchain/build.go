package gotoolchain

import (
	"fmt"
	"go/build"
	"os"
	"path/filepath"
	"runtime"
	"sync"

	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/goversion"
)

// Config describes one executable build. The main package lives in a module
// whose dependencies are vendored; standard packages come from GOROOT.
type Config struct {
	// GOROOT holds the sources and assembly headers of release Version().
	GOROOT string
	// ModuleRoot contains go.mod and vendor/modules.txt for ModulePath. Its
	// contents must not change, because dependency plans are cached by path.
	ModuleRoot string
	ModulePath string
	// Dir and ImportPath identify the main package within the module.
	Dir        string
	ImportPath string
	Tags       []string
	// GCFlags and LDFlags use the go command's spelling, such as
	// "all=-N -l", and are recorded in the executable's build information.
	GCFlags  string
	LDFlags  string
	Trimpath bool
	// Cache holds package archives and dependency plans shared by builds.
	Cache string
	// Environment is the base environment for tool processes.
	Environment []string
	Output      string
}

type builder struct {
	Config
	context build.Context
	modules []*vendoredModule
	mainGo  string          // the main module's go version
	loaded  map[string]*pkg // by directory
	order   []*pkg          // dependencies before dependents
}

// Build compiles the main package and its dependencies with the copied tools
// and links Output. Archives are reused from Cache when their inputs match.
func Build(config Config) error {
	if err := Supported(config.GOROOT); err != nil {
		return err
	}
	b := &builder{Config: config, context: buildContext(config), loaded: map[string]*pkg{}}
	root, err := b.loadMain()
	if err != nil {
		return err
	}
	for _, p := range b.order {
		p.key = b.archiveKey(p)
		p.archive = filepath.Join(b.Cache, p.key[:2], p.key+".a")
		p.done = make(chan struct{})
	}
	for _, p := range b.order {
		go func() {
			defer close(p.done)
			for _, dependency := range p.imports {
				if <-dependency.done; dependency.err != nil {
					p.err = dependency.err
					return
				}
			}
			p.err = b.compile(p)
		}()
	}
	for _, p := range b.order {
		if <-p.done; p.err != nil {
			return p.err
		}
	}
	return b.link(root)
}

// buildContext matches the files the go command would select for the target.
func buildContext(config Config) build.Context {
	context := build.Default
	context.GOROOT = config.GOROOT
	context.GOPATH = ""
	context.GOOS = buildcfg.GOOS
	context.GOARCH = buildcfg.GOARCH
	context.CgoEnabled = false
	context.Compiler = "gc"
	context.BuildTags = config.Tags
	context.ToolTags = append([]string{}, buildcfg.ToolTags...)
	context.ReleaseTags = nil
	for minor := 1; minor <= goversion.Version; minor++ {
		context.ReleaseTags = append(context.ReleaseTags, fmt.Sprintf("go1.%d", minor))
	}
	return context
}

// Tool processes are limited per process rather than per build, so
// concurrent builds share processors and compile a shared archive once.
var (
	toolSlots = make(chan struct{}, runtime.GOMAXPROCS(0))
	inFlight  sync.Map // archive path -> *flight
)

type flight struct {
	done chan struct{}
	err  error
}

// compile builds p's archive unless it is cached or another build in this
// process is building it. Other processes may build the same archive; each
// publishes identical content with an atomic rename.
func (b *builder) compile(p *pkg) error {
	if _, err := os.Stat(p.archive); err == nil {
		return nil
	}
	current := &flight{done: make(chan struct{})}
	if other, building := inFlight.LoadOrStore(p.archive, current); building {
		<-other.(*flight).done
		return other.(*flight).err
	}
	defer func() {
		inFlight.Delete(p.archive)
		close(current.done)
	}()
	// A build that finished between the first check and LoadOrStore has
	// already published the archive.
	if _, err := os.Stat(p.archive); err == nil {
		return nil
	}
	toolSlots <- struct{}{}
	defer func() { <-toolSlots }()
	current.err = b.compileArchive(p)
	if current.err != nil {
		current.err = fmt.Errorf("%s: %w", p.path, current.err)
	}
	return current.err
}
