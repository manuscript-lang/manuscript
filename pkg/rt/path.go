package rt

import (
	"path"
	goruntime "runtime"
	"strings"
)

// pathRules selects POSIX or Windows path conventions.
type pathRules struct{ windows bool }

var _ PathOperations = pathRules{}

func pathHost() pathRules { return pathRules{goruntime.GOOS == "windows"} }

func (p pathRules) slash(s string) string {
	if p.windows {
		return strings.ReplaceAll(s, "\\", "/")
	}
	return s
}
func (p pathRules) native(s string) string {
	if p.windows {
		return strings.ReplaceAll(s, "/", "\\")
	}
	return s
}
func (p pathRules) root(s string) string {
	s = p.slash(s)
	if p.windows {
		if len(s) >= 2 && ((s[0] >= 'A' && s[0] <= 'Z') || (s[0] >= 'a' && s[0] <= 'z')) && s[1] == ':' {
			if len(s) > 2 && s[2] == '/' {
				return s[:3]
			}
			return s[:2]
		}
		if strings.HasPrefix(s, "//") {
			start := 2
			for start < len(s) && s[start] == '/' {
				start++
			}
			serverEnd := strings.IndexByte(s[start:], '/')
			if serverEnd >= 0 {
				serverEnd += start
				shareStart := serverEnd + 1
				for shareStart < len(s) && s[shareStart] == '/' {
					shareStart++
				}
				if shareStart < len(s) {
					shareEnd := strings.IndexByte(s[shareStart:], '/')
					if shareEnd < 0 {
						return s
					}
					return s[:shareStart+shareEnd+1]
				}
			}
		}

	}
	if strings.HasPrefix(s, "/") {
		return "/"
	}
	return ""
}
func (p pathRules) absolute(s string) bool {
	root := p.root(s)
	return strings.HasSuffix(root, "/") || p.windows && strings.HasPrefix(root, "//")
}
func (p pathRules) normalize(s string) string {
	s = p.slash(s)
	if s == "" {
		return "."
	}
	root := p.root(s)
	tail := s[len(root):]
	if p.windows && strings.HasPrefix(root, "//") && !strings.HasSuffix(root, "/") {
		root += "/"
	}

	var stack []string
	for _, part := range strings.Split(tail, "/") {
		switch part {
		case "", ".":
		case "..":
			if len(stack) > 0 && stack[len(stack)-1] != ".." {
				stack = stack[:len(stack)-1]
			} else if !strings.HasSuffix(root, "/") {
				stack = append(stack, part)
			}
		default:
			stack = append(stack, part)
		}
	}
	value := root + strings.Join(stack, "/")
	if value == "" {
		value = "."
	}
	if strings.HasSuffix(s, "/") && !strings.HasSuffix(value, "/") {
		value += "/"
	}
	if p.windows && len(root) == 2 && len(stack) == 0 {
		value = root + "."
	}
	// A relative first component shaped like a drive ("./C:") must not become
	// a drive-relative path once the leading "." is removed.
	if p.windows && root == "" && len(stack) > 0 && p.root(stack[0]) != "" {
		value = "./" + value
	}
	return p.native(value)
}
func (p pathRules) parse(original string) *PathParts {
	s := p.slash(original)
	root := p.root(s)
	trimmed := strings.TrimRight(s, "/")
	base := ""
	dir := ""
	rootOriginal := original[:len(root)]
	if len(trimmed) > len(strings.TrimRight(root, "/")) {
		at := strings.LastIndex(trimmed, "/")
		base = trimmed[at+1:]
		if at >= 0 {
			dir = original[:at]
		}
		if p.windows && len(root) == 2 && at < 0 {
			base = trimmed[2:]
			dir = rootOriginal
		}
		if len(dir) < len(root) {
			dir = rootOriginal
		}
	}
	if base == "" && root != "" {
		dir = rootOriginal
	}
	ext := path.Ext(base)
	if base == "." || base == ".." || strings.HasPrefix(base, ".") && strings.Count(base, ".") == 1 {
		ext = ""
	}
	return &PathParts{Root: rootOriginal, Directory: dir, Base: base, Extension: ext, Name: strings.TrimSuffix(base, ext)}
}
func (p pathRules) resolve(base string, parts []string) (string, bool) {
	if !p.absolute(base) || strings.ContainsRune(base, 0) {
		return "", false
	}
	for _, part := range parts {
		if strings.ContainsRune(part, 0) {
			return "", false
		}
	}
	value := p.slash(base)
	if p.windows {
		// Resolve from the last component: absolute paths supersede earlier tails,
		// while an earlier absolute path on the chosen drive supplies its base.
		// A drive without an explicit base would need ambient per-drive cwd.
		device, tail, absolute := "", "", false
		components := append([]string{base}, parts...)
		for i := len(components) - 1; i >= 0; i-- {
			part := p.slash(components[i])
			if part == "" {
				continue
			}
			root := p.root(part)
			partDevice := strings.TrimSuffix(root, "/")
			if partDevice != "" {
				if device != "" && !strings.EqualFold(device, partDevice) {
					continue
				}
				device = partDevice
			}
			if !absolute {
				tail = part[len(root):] + "/" + tail
				absolute = p.absolute(part)
			}
			if absolute && device != "" {
				break
			}
		}
		if !absolute {
			return "", false
		}
		value = device + "/" + tail
	} else {
		for _, part := range parts {
			if p.absolute(part) {
				value = part
			} else if part != "" {
				value = strings.TrimRight(value, "/") + "/" + part
			}
		}
	}
	normalized := p.normalize(value)
	if normalized != p.native(p.root(normalized)) {
		normalized = strings.TrimSuffix(normalized, p.native("/"))
	}
	return normalized, true
}

func (p pathRules) Separator(*Execution) string { return p.native("/") }
func (p pathRules) Delimiter(*Execution) string {
	if p.windows {
		return ";"
	}
	return ":"
}
func (p pathRules) Normalize(_ *Execution, s string) string { return p.normalize(s) }
func (p pathRules) Parse(_ *Execution, s string) *PathParts { return p.parse(s) }
func (p pathRules) Extension(_ *Execution, s string) string { return p.parse(s).Extension }
func (p pathRules) IsAbsolute(_ *Execution, s string) bool  { return p.absolute(s) }

func (p pathRules) Basename(_ *Execution, raw string) string { return p.basename(raw, "", false) }
func (p pathRules) BasenameWithout(_ *Execution, raw, suffix string) string {
	return p.basename(raw, suffix, true)
}
func (p pathRules) basename(raw, suffix string, strip bool) string {
	original := p.slash(raw)
	prefix := 0
	if p.windows && len(original) >= 2 && original[1] == ':' && ((original[0] >= 'a' && original[0] <= 'z') || (original[0] >= 'A' && original[0] <= 'Z')) {
		prefix = 2
		original = original[2:]
	}
	base := strings.TrimRight(original, "/")
	if at := strings.LastIndexByte(base, '/'); at >= 0 {
		base = base[at+1:]
	}
	if strip && suffix != "" && len(suffix) <= len(raw) {
		if raw == suffix {
			return ""
		}
		if base == "" {
			return raw[prefix:]
		}
		if suffix != base {
			base = strings.TrimSuffix(base, suffix)
		}
	}
	return base
}

func (p pathRules) Dirname(_ *Execution, original string) string {
	s := p.slash(original)
	root := p.root(s)
	s = strings.TrimRight(s, "/")
	at := strings.LastIndex(s, "/")
	if at < 0 {
		if root != "" {
			return original[:len(root)]
		}
		return "."
	}
	if at < len(root) {
		return original[:len(root)]
	}
	return original[:at]
}

func (p pathRules) Join(_ *Execution, items *List[string]) string {
	var parts []string
	for _, part := range items.Items {
		if part != "" {
			parts = append(parts, part)
		}
	}
	joined := strings.Join(parts, "/")
	if p.windows && strings.HasPrefix(p.slash(joined), "//") {
		first := p.slash(parts[0])
		unc := len(first) > 2 && first[:2] == "//" && first[2] != '/'
		if !unc {
			joined = "/" + strings.TrimLeft(p.slash(joined), "/")
		}
	}
	return p.normalize(joined)
}

func (p pathRules) Resolve(_ *Execution, base string, parts *List[string]) Result[string, PathError] {
	v, ok := p.resolve(base, parts.Items)
	if !ok {
		return Fail[string, PathError](PathError_InvalidInput{})
	}
	return Ok[string, PathError](v)
}

func (p pathRules) Relative(_ *Execution, baseArg, targetArg string) Result[string, PathError] {
	base, ok := p.resolve(baseArg, nil)
	target, ok2 := p.resolve(targetArg, nil)
	if !ok || !ok2 {
		return Fail[string, PathError](PathError_InvalidInput{})
	}
	b, t := p.slash(base), p.slash(target)
	equal := func(x, y string) bool {
		if p.windows {
			return strings.EqualFold(x, y)
		}
		return x == y
	}
	if !equal(p.root(b), p.root(t)) {
		return Ok[string, PathError](target)
	}
	bs, ts := strings.Split(strings.TrimPrefix(b, p.root(b)), "/"), strings.Split(strings.TrimPrefix(t, p.root(t)), "/")
	if len(bs) == 1 && bs[0] == "" {
		bs = nil
	}
	if len(ts) == 1 && ts[0] == "" {
		ts = nil
	}
	i := 0
	for i < len(bs) && i < len(ts) && equal(bs[i], ts[i]) {
		i++
	}
	out := make([]string, len(bs)-i)
	for j := range out {
		out[j] = ".."
	}
	out = append(out, ts[i:]...)
	return Ok[string, PathError](p.native(strings.Join(out, "/")))
}

func (p pathRules) Format(_ *Execution, f *PathParts) string {
	dir := f.Directory
	if dir == "" {
		dir = f.Root
	}
	base := f.Base
	if base == "" {
		ext := f.Extension
		if ext != "" && !strings.HasPrefix(ext, ".") {
			ext = "." + ext
		}
		base = f.Name + ext
	}
	if dir == "" {
		return base
	}
	if dir == f.Root {
		return dir + base
	}
	return dir + p.native("/") + base
}

func (p pathRules) ToNamespacedPath(_ *Execution, s string) string {
	root := p.root(s)
	if !p.windows || !p.absolute(s) || root == "/" || strings.HasPrefix(s, "\\\\?\\") || strings.HasPrefix(s, "\\\\.\\") {
		return s
	}
	resolved, ok := p.resolve(s, nil)
	if !ok {
		return s
	}
	if strings.HasPrefix(resolved, "\\\\") {
		return "\\\\?\\UNC\\" + resolved[2:]
	}
	return "\\\\?\\" + resolved
}

func (p pathRules) MatchesGlob(_ *Execution, value, glob string) Result[bool, PathError] {
	pattern := p.slash(glob)
	if !pathGlobValid(pattern) {
		return Fail[bool, PathError](PathError_InvalidInput{})
	}
	return Ok[bool, PathError](pathGlobMatch(p.slash(value), pattern))
}

// Path_Posix returns path operations with POSIX rules.
func Path_Posix(_ *Execution) PathOperations { return pathRules{false} }

// Path_Win32 returns path operations with Windows rules.
func Path_Win32(_ *Execution) PathOperations { return pathRules{true} }

func Path_Basename(ctx *Execution, s string) string { return pathHost().Basename(ctx, s) }
func Path_Dirname(ctx *Execution, s string) string  { return pathHost().Dirname(ctx, s) }
func Path_Extension(ctx *Execution, s string) string {
	return pathHost().Extension(ctx, s)
}
func Path_IsAbsolute(ctx *Execution, s string) bool { return pathHost().IsAbsolute(ctx, s) }
func Path_Join(ctx *Execution, parts *List[string]) string {
	return pathHost().Join(ctx, parts)
}
func Path_Normalize(ctx *Execution, s string) string { return pathHost().Normalize(ctx, s) }
func Path_Relative(ctx *Execution, base, target string) Result[string, PathError] {
	return pathHost().Relative(ctx, base, target)
}
func Path_BasenameWithout(ctx *Execution, s, suffix string) string {
	return pathHost().BasenameWithout(ctx, s, suffix)
}
func Path_Resolve(ctx *Execution, base string, parts *List[string]) Result[string, PathError] {
	return pathHost().Resolve(ctx, base, parts)
}
func Path_Parse(ctx *Execution, s string) *PathParts { return pathHost().Parse(ctx, s) }
func Path_Format(ctx *Execution, parts *PathParts) string {
	return pathHost().Format(ctx, parts)
}
func Path_Separator(ctx *Execution) string { return pathHost().Separator(ctx) }
func Path_Delimiter(ctx *Execution) string { return pathHost().Delimiter(ctx) }
func Path_ToNamespacedPath(ctx *Execution, s string) string {
	return pathHost().ToNamespacedPath(ctx, s)
}
func Path_MatchesGlob(ctx *Execution, value, pattern string) Result[bool, PathError] {
	return pathHost().MatchesGlob(ctx, value, pattern)
}

// Errors_Message_PathError returns the fixed path diagnostic.
func Errors_Message_PathError(_ *Execution, e PathError) string {
	return dfMessage("path", reasonInvalidInput)
}
