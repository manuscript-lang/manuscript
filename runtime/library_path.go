package msruntime

import (
	"path"
	goruntime "runtime"
	"strings"
)

type libraryPaths struct{ windows bool }

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	methods := []LibraryMethod{
		{"PathOperations", "basename", "String", []LibraryParam{p("path", "String")}},
		{"PathOperations", "basename_without", "String", []LibraryParam{p("path", "String"), p("suffix", "String")}},
		{"PathOperations", "dirname", "String", []LibraryParam{p("path", "String")}},
		{"PathOperations", "extension", "String", []LibraryParam{p("path", "String")}},
		{"PathOperations", "is_absolute", "Bool", []LibraryParam{p("path", "String")}},
		{"PathOperations", "join", "String", []LibraryParam{p("parts", "List[String]")}},
		{"PathOperations", "normalize", "String", []LibraryParam{p("path", "String")}},
		{"PathOperations", "relative", libraryResult("String", "PathError"), []LibraryParam{p("base", "String"), p("target", "String")}},
		{"PathOperations", "resolve", libraryResult("String", "PathError"), []LibraryParam{p("base", "String"), p("parts", "List[String]")}},
		{"PathOperations", "parse", "PathParts", []LibraryParam{p("path", "String")}},
		{"PathOperations", "format", "String", []LibraryParam{p("parts", "PathParts")}},
		{"PathOperations", "separator", "String", nil},
		{"PathOperations", "delimiter", "String", nil},
		{"PathOperations", "to_namespaced_path", "String", []LibraryParam{p("path", "String")}},
		{"PathOperations", "matches_glob", libraryResult("Bool", "PathError"), []LibraryParam{p("path", "String"), p("pattern", "String")}},
	}
	LibraryMethods = append(LibraryMethods, methods...)
	for _, m := range methods {
		spec := m

		libraryAdd("path", spec.Name, spec.Result, spec.Params, func(ctx *Execution, r string, a []Value) Value {
			return (libraryPaths{goruntime.GOOS == "windows"}).call(ctx, r, spec.Name, a)
		})
	}
	for name, windows := range map[string]bool{"posix": false, "win32": true} {
		win := windows
		libraryAdd("path", name, "PathOperations", nil, func(_ *Execution, _ string, _ []Value) Value {
			return ViewOf("@std/PathOperations", libraryPaths{win})
		})
	}
}
func (p libraryPaths) Operation(name string) Function {
	return libraryMethod("PathOperations", name, func(ctx *Execution, r string, a []Value) Value { return p.call(ctx, r, name, a) })
}
func (p libraryPaths) slash(s string) string {
	if p.windows {
		return strings.ReplaceAll(s, "\\", "/")
	}
	return s
}
func (p libraryPaths) native(s string) string {
	if p.windows {
		return strings.ReplaceAll(s, "/", "\\")
	}
	return s
}
func (p libraryPaths) root(s string) string {
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
func (p libraryPaths) absolute(s string) bool {
	root := p.root(s)
	return strings.HasSuffix(root, "/") || p.windows && strings.HasPrefix(root, "//")
}
func (p libraryPaths) normalize(s string) string {
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
	return p.native(value)
}
func (p libraryPaths) parse(original string) Record {
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
	return Record{"@std/PathParts", map[string]Value{"root": rootOriginal, "directory": dir, "base": base, "extension": ext, "name": strings.TrimSuffix(base, ext)}}
}
func (p libraryPaths) resolve(base string, parts []string) (string, bool) {
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
func (p libraryPaths) call(_ *Execution, r, name string, a []Value) Value {
	switch name {
	case "separator":
		return p.native("/")
	case "delimiter":
		if p.windows {
			return ";"
		}
		return ":"
	case "normalize":
		return p.normalize(a[0].(string))
	case "parse":
		return p.parse(a[0].(string))
	case "basename", "basename_without":
		raw := a[0].(string)
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
		if name == "basename_without" {
			suffix := a[1].(string)
			if suffix != "" && len(suffix) <= len(raw) {
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
		}
		return base
	case "extension":
		return p.parse(a[0].(string)).Fields["extension"]
	case "dirname":
		original := a[0].(string)
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
	case "is_absolute":
		return p.absolute(a[0].(string))
	case "join":
		var parts []string
		for _, part := range libraryStringValues(a[0]) {
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
	case "resolve":
		v, ok := p.resolve(a[0].(string), libraryStringValues(a[1]))
		if !ok {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, v)
	case "relative":
		base, ok := p.resolve(a[0].(string), nil)
		target, ok2 := p.resolve(a[1].(string), nil)
		if !ok || !ok2 {
			return libraryError(r, "InvalidInput", "")
		}
		b, t := p.slash(base), p.slash(target)
		equal := func(x, y string) bool {
			if p.windows {
				return strings.EqualFold(x, y)
			}
			return x == y
		}
		if !equal(p.root(b), p.root(t)) {
			return libraryOK(r, target)
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
		return libraryOK(r, p.native(strings.Join(out, "/")))
	case "format":
		f := a[0].(Record).Fields
		dir := f["directory"].(string)
		if dir == "" {
			dir = f["root"].(string)
		}
		base := f["base"].(string)
		if base == "" {
			ext := f["extension"].(string)
			if ext != "" && !strings.HasPrefix(ext, ".") {
				ext = "." + ext
			}
			base = f["name"].(string) + ext
		}
		if dir == "" {
			return base
		}
		if dir == f["root"].(string) {
			return dir + base
		}
		return dir + p.native("/") + base
	case "to_namespaced_path":
		s := a[0].(string)
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
	case "matches_glob":
		pattern := p.slash(a[1].(string))
		if !libraryValidGlob(pattern) {
			return libraryError(r, "InvalidInput", "")
		}
		return libraryOK(r, libraryGlobMatch(p.slash(a[0].(string)), pattern))
	}
	return Panic("unknown path operation")
}
