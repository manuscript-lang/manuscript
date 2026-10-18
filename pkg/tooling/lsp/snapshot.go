package lsp

import (
	"path/filepath"

	"github.com/manuscript-lang/manuscript/pkg/checker"
	"github.com/manuscript-lang/manuscript/pkg/compiler"
	"github.com/manuscript-lang/manuscript/pkg/tooling"
)

type analysisKey struct {
	target string
	module string
}

// Two URI spellings can decode to the same filename. analyzeWith deliberately
// lets the requested document win that overlay key; divergent text therefore
// cannot share a result, even within one generation. CanonicalOverlay still
// owns distinct-path symlink conflicts and confinement validation.
func (s *server) canShareOverlays() bool {
	if s.overlayChecked {
		return s.shareOverlays
	}
	seen := map[string]string{}
	s.shareOverlays = true
	for _, d := range s.docs {
		path := filename(d.URI)
		if text, ok := seen[path]; ok && text != d.Text {
			s.shareOverlays = false
			break
		}
		seen[path] = d.Text
	}
	s.overlayChecked = true
	return s.shareOverlays
}

// compileSnapshot is used only by ordinary recovering open-document analysis.
// A selected fallback never replaces the default manifest entry. Strict
// workspace and repaired ScopeMarker analyses remain uncached and transient.
func (s *server) compileSnapshot(target string, options compiler.Options) compiler.Result {
	identity := target
	// FindManifest has already selected the nearest spelling, including invalid
	// nested manifests. Only then canonicalize an existing target for reuse.
	if filepath.Base(target) == "ms.toml" {
		// ReadProject resolves the containing directory, not a symlinked
		// manifest file's destination. Standalone files also retain their
		// selected source root; resolving the file itself could erase an escape.
		if root, err := filepath.EvalSymlinks(filepath.Dir(target)); err == nil {
			identity = filepath.Join(root, "ms.toml")
		}
	}
	key := analysisKey{identity, options.Module}
	if result, ok := s.analyses[key]; ok {
		return result
	}
	result := compiler.CompileFile(target, options)
	if s.analyses == nil {
		s.analyses = map[analysisKey]compiler.Result{}
	}
	s.analyses[key] = result
	return result
}

// These derived facts contain checked identities and belong to the same live
// generation as their Program. Invalidation releases them with the analyses.
func (s *server) documentIndex(result compiler.Result) []occurrence {
	if result.Program == nil {
		return nil
	}
	if index, ok := s.indices[result.Program]; ok {
		return index
	}
	index := sourceIndex(result)
	if s.indices == nil {
		s.indices = map[*checker.Program][]occurrence{}
	}
	s.indices[result.Program] = index
	return index
}

func (s *server) programLint(result compiler.Result) []tooling.LintFinding {
	if result.Program == nil {
		return nil
	}
	if findings, ok := s.lints[result.Program]; ok {
		return findings
	}
	findings := tooling.LintProgram(result.Program)
	if s.lints == nil {
		s.lints = map[*checker.Program][]tooling.LintFinding{}
	}
	s.lints[result.Program] = findings
	return findings
}

func (s *server) requestCanceled(r *request) bool {
	return len(r.ID) > 0 && s.transport != nil && s.transport.canceled(r.ID)
}
