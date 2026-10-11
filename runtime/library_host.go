package msruntime

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"

	"math/big"
	"net/http"

	"net/url"
	"os"
	"path/filepath"
	goruntime "runtime"
	"sort"

	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

type LibraryMethod struct {
	Receiver, Name, Result string
	Params                 []LibraryParam
}

var LibraryMethods = []LibraryMethod{
	{"FileSystem", "read_file", libraryResult("Bytes"), []LibraryParam{{"path", "String"}, {"max_bytes", "Int"}}},
	{"FileSystem", "write_file", libraryResult("Unit"), []LibraryParam{{"path", "String"}, {"data", "Bytes"}, {"replace", "Bool"}}},
	{"FileSystem", "stat", libraryResult("FileInfo"), []LibraryParam{{"path", "String"}, {"follow_links", "Bool"}}},
	{"FileSystem", "list", libraryResult("List[DirectoryEntry]"), []LibraryParam{{"path", "String"}, {"max_entries", "Int"}}},
	{"FileSystem", "create_directory", libraryResult("Unit"), []LibraryParam{{"path", "String"}, {"recursive", "Bool"}}},
	{"FileSystem", "remove", libraryResult("Unit"), []LibraryParam{{"path", "String"}, {"recursive", "Bool"}}},
	{"FileSystem", "rename", libraryResult("Unit"), []LibraryParam{{"source", "String"}, {"destination", "String"}}},
	{"FileSystem", "copy_file", libraryResult("Unit"), []LibraryParam{{"source", "String"}, {"destination", "String"}, {"replace", "Bool"}, {"max_bytes", "Int"}}},
	{"FileSystem", "canonicalize", libraryResult("String"), []LibraryParam{{"path", "String"}}},
	{"FileSystem", "read_link", libraryResult("String"), []LibraryParam{{"path", "String"}}},
	{"FileSystem", "create_link", libraryResult("Unit"), []LibraryParam{{"path", "String"}, {"target", "String"}}},
	{"FileSystem", "temporary_directory", libraryResult("String"), []LibraryParam{{"prefix", "String"}}},
	{"Entropy", "bytes", libraryResult("Bytes"), []LibraryParam{{"count", "Int"}}},
	{"WallClock", "now", "Timestamp", nil},
	{"System", "info", "SystemInfo", nil},
	{"System", "working_directory", "String", nil},
	{"System", "environment", "Optional[String]", []LibraryParam{{"name", "String"}}},
	{"Network", "request", libraryResult("ClientResponse"), []LibraryParam{{"method", "String"}, {"url", "String"}, {"headers", "Map[String][String]"}, {"body", "Bytes"}, {"max_response_bytes", "Int"}, {"timeout", "Duration"}}},
	{"Network", "lookup", libraryResult("List[String]"), []LibraryParam{{"name", "String"}, {"max_records", "Int"}, {"timeout", "Duration"}}},
}

func libraryMethod(receiver, name string, body func(*Execution, string, []Value) Value) Function {
	for _, spec := range LibraryMethods {
		if spec.Receiver == receiver && spec.Name == name {
			labels := []string{}
			for _, p := range spec.Params {
				labels = append(labels, p.Name)
			}
			result := libraryRuntimeType(spec.Result)
			return NewFunction(labels, result, func(ctx *Execution, a []Value) Value { return body(ctx, result, a) })
		}
	}
	Panic("unknown library method " + receiver + "." + name)
	return Function{}
}
func libraryRuntimeType(s string) string { // qualified runtime keys, preserving intrinsic identifiers
	var b strings.Builder
	for i := 0; i < len(s); {
		if s[i] >= 'A' && s[i] <= 'Z' {
			start := i
			for i < len(s) && (s[i] >= 'A' && s[i] <= 'Z' || s[i] >= 'a' && s[i] <= 'z') {
				i++
			}
			name := s[start:i]
			switch name {
			case "Bool", "Int", "Float", "String", "Unit", "Never", "Shareable":
			default:
				b.WriteString("@std/")
			}
			b.WriteString(name)
		} else {
			b.WriteByte(s[i])
			i++
		}
	}
	return b.String()
}

type libraryTimestamp struct{ t time.Time }
type libraryWallClock struct{}

func (libraryWallClock) Operation(name string) Function {
	return libraryMethod("WallClock", name, func(_ *Execution, _ string, _ []Value) Value { return libraryTimestamp{time.Now().UTC()} })
}

type librarySystem struct{ directory string }

func (s *librarySystem) Operation(name string) Function {
	return libraryMethod("System", name, func(_ *Execution, _ string, a []Value) Value {
		switch name {
		case "info":
			return Record{"@std/SystemInfo", map[string]Value{"os": goruntime.GOOS, "architecture": goruntime.GOARCH, "cpu_count": int64(goruntime.NumCPU())}}
		case "working_directory":
			return s.directory
		case "environment":
			v, ok := os.LookupEnv(a[0].(string))
			if !utf8.ValidString(v) {
				ok = false
			}
			return optional("String", v, ok)
		}
		return Panic("unknown system operation")
	})
}

type libraryEntropy struct{}

func (libraryEntropy) Operation(name string) Function {
	return libraryMethod("Entropy", name, func(ctx *Execution, r string, a []Value) Value {
		n := a[0].(int64)
		if n < 0 || n > 16*1024*1024 {
			return libraryError(r, "InvalidInput", "")
		}
		b := make([]byte, int(n))
		for offset := 0; offset < len(b); {
			CheckCancelled(ctx)
			end := offset + 65536
			if end > len(b) {
				end = len(b)
			}
			if _, err := rand.Read(b[offset:end]); err != nil {
				return libraryError(r, "Failed", err.Error())
			}
			offset = end
		}
		return libraryOK(r, Bytes{b})
	})
}

type libraryFileSystem struct{ directory string }

func (f *libraryFileSystem) path(s string) (string, bool) {
	if strings.ContainsRune(s, 0) {
		return "", false
	}
	if !filepath.IsAbs(s) {
		s = filepath.Join(f.directory, s)
	}
	return s, true
}
func libraryOSResult(r string, value Value, err error) Value {
	if err == nil {
		return libraryOK(r, value)
	}
	code := "Failed"
	switch {
	case errors.Is(err, os.ErrNotExist):
		code = "NotFound"
	case errors.Is(err, os.ErrExist):
		code = "AlreadyExists"
	case errors.Is(err, os.ErrPermission):
		code = "PermissionDenied"
	}
	return libraryError(r, code, err.Error())
}
func (f *libraryFileSystem) Operation(name string) Function {
	return libraryMethod("FileSystem", name, func(ctx *Execution, r string, a []Value) Value {
		if name == "temporary_directory" {
			prefix := a[0].(string)
			if prefix == "" || strings.ContainsAny(prefix, "/\\\x00") {
				return libraryError(r, "InvalidInput", "")
			}
			s, err := os.MkdirTemp("", prefix)
			if err == nil && ctx.Context.Err() != nil {
				os.Remove(s)
				CheckCancelled(ctx)
			}
			return libraryOSResult(r, s, err)
		}
		p, ok := f.path(a[0].(string))
		if !ok {
			return libraryError(r, "InvalidInput", "")
		}
		switch name {
		case "read_file":
			n := a[1].(int64)
			if n < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			file, err := os.Open(p)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			defer file.Close()
			b, code := libraryReadBounded(ctx, file, n)
			if code != "" {
				return libraryError(r, code, "")
			}
			return libraryOK(r, Bytes{b})
		case "write_file":
			flags := os.O_WRONLY | os.O_CREATE | os.O_EXCL
			if a[2].(bool) {
				flags = os.O_WRONLY | os.O_CREATE | os.O_TRUNC
			}
			file, err := os.OpenFile(p, flags, 0600)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			defer file.Close()
			data := a[1].(Bytes).Items
			for len(data) > 0 {
				CheckCancelled(ctx)
				n := len(data)
				if n > 65536 {
					n = 65536
				}
				written, err := file.Write(data[:n])
				if err != nil {
					return libraryOSResult(r, nil, err)
				}
				if written == 0 {
					return libraryError(r, "Failed", "short write")
				}
				data = data[written:]
			}
			return libraryOSResult(r, Unit{}, file.Close())
		case "stat":
			var info os.FileInfo
			var err error
			if a[1].(bool) {
				info, err = os.Stat(p)
			} else {
				info, err = os.Lstat(p)
			}
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			if !utf8.ValidString(info.Name()) {
				return libraryError(r, "Unsupported", "")
			}
			return libraryOK(r, Record{"@std/FileInfo", map[string]Value{"name": info.Name(), "size": info.Size(), "directory": info.IsDir(), "symlink": info.Mode()&os.ModeSymlink != 0, "modified": libraryTimestamp{info.ModTime().UTC()}}})
		case "list":
			n := a[1].(int64)
			if n < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			directory, err := os.Open(p)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			defer directory.Close()
			var entries []Value
			for {
				CheckCancelled(ctx)
				batch, err := directory.ReadDir(64)
				for _, e := range batch {
					if int64(len(entries)) >= n {
						return libraryError(r, "LimitExceeded", "")
					}
					if !utf8.ValidString(e.Name()) {
						return libraryError(r, "Unsupported", "")
					}
					entries = append(entries, Record{"@std/DirectoryEntry", map[string]Value{"name": e.Name(), "directory": e.IsDir(), "symlink": e.Type()&os.ModeSymlink != 0}})
				}
				if err == io.EOF {
					break
				}
				if err != nil {
					return libraryOSResult(r, nil, err)
				}
			}
			sort.Slice(entries, func(i, j int) bool {
				return entries[i].(Record).Fields["name"].(string) < entries[j].(Record).Fields["name"].(string)
			})
			return libraryOK(r, libraryList("@std/DirectoryEntry", entries))
		case "create_directory":
			var err error
			if a[1].(bool) {
				err = os.MkdirAll(p, 0700)
			} else {
				err = os.Mkdir(p, 0700)
			}
			return libraryOSResult(r, Unit{}, err)
		case "remove":
			var err error
			if a[1].(bool) {
				err = libraryRemoveTree(ctx, p)
			} else {
				err = os.Remove(p)
			}
			return libraryOSResult(r, Unit{}, err)
		case "rename":
			destination, ok := f.path(a[1].(string))
			if !ok {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOSResult(r, Unit{}, os.Rename(p, destination))
		case "copy_file":
			destination, ok := f.path(a[1].(string))
			n := a[3].(int64)
			if !ok || n < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			source, err := os.Open(p)
			if err != nil {
				return libraryOSResult(r, nil, err)
			}
			defer source.Close()
			b, code := libraryReadBounded(ctx, source, n)
			if code != "" {
				return libraryError(r, code, "")
			}
			return f.Operation("write_file").Body(ctx, []Value{destination, Bytes{b}, a[2]})
		case "canonicalize":
			s, err := filepath.EvalSymlinks(p)
			if !utf8.ValidString(s) {
				return libraryError(r, "Unsupported", "")
			}
			return libraryOSResult(r, s, err)
		case "read_link":
			s, err := os.Readlink(p)
			if !utf8.ValidString(s) {
				return libraryError(r, "Unsupported", "")
			}
			return libraryOSResult(r, s, err)
		case "create_link":
			target := a[1].(string)
			if strings.ContainsRune(target, 0) {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOSResult(r, Unit{}, os.Symlink(target, p))
		}
		return Panic("unknown filesystem operation")
	})
}
func libraryRemoveTree(ctx *Execution, p string) error {
	CheckCancelled(ctx)
	info, err := os.Lstat(p)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return os.Remove(p)
	}
	root, err := os.OpenRoot(p)
	if err != nil {
		return err
	}
	defer root.Close()
	return libraryRemoveRoot(ctx, root, ".")
}
func libraryRemoveRoot(ctx *Execution, root *os.Root, p string) error {
	CheckCancelled(ctx)
	file, err := root.Open(p)
	if err != nil {
		return err
	}
	defer file.Close()
	for {
		batch, err := file.ReadDir(64)
		for _, entry := range batch {
			child := filepath.Join(p, entry.Name())
			if entry.IsDir() {
				if err := libraryRemoveRoot(ctx, root, child); err != nil {
					return err
				}
			} else {
				if err := root.Remove(child); err != nil {
					return err
				}
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		CheckCancelled(ctx)
	}
	if p == "." {
		return os.Remove(root.Name())
	}
	return root.Remove(p)
}
func libraryNetworkRequest(n *network, ctx *Execution, r string, a []Value) Value {
	n.mu.Lock()
	closed := n.closed
	n.mu.Unlock()
	if closed {
		return libraryError(r, "Closed", "")
	}
	method, address := a[0].(string), a[1].(string)
	max, timeout := a[4].(int64), a[5].(Duration)
	if max < 0 || timeout < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	u, err := url.Parse(address)
	if err != nil || u.Host == "" || u.User != nil || u.Scheme != "http" && u.Scheme != "https" {
		return libraryError(r, "InvalidInput", "")
	}
	call, cancel := contextWithLibraryTimeout(ctx, timeout)
	defer cancel()
	call, finish, admitted := n.beginCall(call)
	if !admitted {
		return libraryError(r, "Closed", "")
	}
	defer finish()
	req, err := http.NewRequestWithContext(call, method, address, strings.NewReader(string(a[3].(Bytes).Items)))
	if err != nil {
		return libraryError(r, "InvalidInput", "")
	}
	for _, e := range a[2].(Map).Entries {
		name, value := e.Key.(string), e.Value.(string)
		if !libraryHeaderName(name) || strings.ContainsAny(value, "\r\n\x00") || strings.EqualFold(name, "Content-Length") || strings.EqualFold(name, "Transfer-Encoding") || strings.EqualFold(name, "Host") {
			return libraryError(r, "InvalidInput", "")
		}
		req.Header.Set(name, value)
	}
	// No ambient proxy or cookie jar. Redirects are returned to the caller for explicit policy decisions.
	transport := &http.Transport{TLSHandshakeTimeout: time.Duration(timeout), MaxResponseHeaderBytes: 64 * 1024, DisableCompression: true, DisableKeepAlives: true, DialContext: n.dial}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	CheckCancelled(ctx)
	if err != nil {
		return n.networkFailure(ctx, r, call, err)
	}
	defer response.Body.Close()
	data, code := libraryReadBounded(ctx, response.Body, max)
	if code != "" {
		if call.Err() != nil {
			if n.isClosed() {
				return libraryError(r, "Closed", "")
			}
			return libraryError(r, "Timeout", "")
		}
		return libraryError(r, code, "")
	}
	headers := Map{Type: "@std/Map[String][@std/List[String]]"}
	keys := []string{}
	for k := range response.Header {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		for _, v := range response.Header[k] {
			if !utf8.ValidString(v) {
				return libraryError(r, "InvalidData", "")
			}
		}
		headers.Entries = append(headers.Entries, Entry{k, libraryStrings(response.Header[k])})
	}
	return libraryOK(r, Record{"@std/ClientResponse", map[string]Value{"status": int64(response.StatusCode), "headers": headers, "body": Bytes{data}}})
}
func libraryHeaderName(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c <= 32 || c >= 127 || strings.ContainsRune("()<>@,;:\\\"/[]?={}", c) {
			return false
		}
	}
	return true
}
func libraryNetworkLookup(n *network, ctx *Execution, r string, a []Value) Value {
	n.mu.Lock()
	closed := n.closed
	n.mu.Unlock()
	if closed {
		return libraryError(r, "Closed", "")
	}
	max, timeout := a[1].(int64), a[2].(Duration)
	if max < 0 || timeout < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	call, cancel := contextWithLibraryTimeout(ctx, timeout)
	defer cancel()
	call, finish, admitted := n.beginCall(call)
	if !admitted {
		return libraryError(r, "Closed", "")
	}
	defer finish()
	if !n.policy.host(a[0].(string)) {
		return libraryError(r, "PermissionDenied", "")
	}
	records, err := n.resolverInstance().LookupHost(call, a[0].(string))
	CheckCancelled(ctx)
	if err != nil {
		if call.Err() != nil {
			if n.isClosed() {
				return libraryError(r, "Closed", "")
			}
			return libraryError(r, "Timeout", "")
		}
		return libraryError(r, "Failed", err.Error())
	}
	if int64(len(records)) > max {
		return libraryError(r, "LimitExceeded", "")
	}
	return libraryOK(r, libraryStrings(records))
}
func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("random", "secure_int", libraryResult("Int"), []LibraryParam{p("entropy", "Entropy&Shareable"), p("min", "Int"), p("max_exclusive", "Int")}, func(ctx *Execution, r string, a []Value) Value {
		min, max := a[1].(int64), a[2].(int64)
		if min >= max {
			return libraryError(r, "InvalidInput", "")
		}
		width := new(big.Int).Sub(big.NewInt(max), big.NewInt(min))
		bits := width.BitLen()
		count := (bits + 7) / 8
		for {
			CheckCancelled(ctx)
			v := Invoke(ctx, Bind(a[0], "", "bytes"), []Argument{{"count", int64(count)}}).(Alternative)
			if v.Tag == "error" {
				return Alternative{r, "error", v.Fields}
			}
			data := append([]byte{}, v.Fields[0].(Bytes).Items...)
			if len(data) != count {
				return libraryError(r, "Failed", "entropy source returned incorrect length")
			}
			data[0] &= byte(255 >> uint(count*8-bits))
			n := new(big.Int).SetBytes(data)
			if n.Cmp(width) < 0 {
				return libraryOK(r, n.Add(n, big.NewInt(min)).Int64())
			}
		}
	})
	libraryAdd("random", "uuid_v4", libraryResult("String"), []LibraryParam{p("entropy", "Entropy&Shareable")}, func(ctx *Execution, r string, a []Value) Value {
		v := Invoke(ctx, Bind(a[0], "", "bytes"), []Argument{{"count", int64(16)}}).(Alternative)
		if v.Tag == "error" {
			return Alternative{r, "error", v.Fields}
		}
		data := append([]byte{}, v.Fields[0].(Bytes).Items...)
		if len(data) != 16 {
			return libraryError(r, "Failed", "entropy source returned incorrect length")
		}
		data[6] = data[6]&15 | 64
		data[8] = data[8]&63 | 128
		return libraryOK(r, fmt.Sprintf("%x-%x-%x-%x-%x", data[:4], data[4:6], data[6:8], data[8:10], data[10:]))
	})
	libraryAdd("time", "timestamp", libraryResult("Timestamp"), []LibraryParam{p("seconds", "Int"), p("nanoseconds", "Int")}, func(_ *Execution, r string, a []Value) Value {
		seconds, ns := a[0].(int64), a[1].(int64)
		if ns < 0 || ns >= 1e9 || seconds < -62135596800 || seconds > 253402300799 {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, libraryTimestamp{time.Unix(seconds, ns).UTC()})
	})
	libraryAdd("time", "parse_timestamp", libraryResult("Timestamp"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		value := a[0].(string)
		if !libraryTimestampPattern.MatchString(value) {
			return libraryError(r, "InvalidData", "")
		}
		if dot := strings.IndexByte(value, '.'); dot >= 0 {
			end := dot + 1
			for end < len(value) && value[end] >= '0' && value[end] <= '9' {
				end++
			}
			if end-dot-1 > 9 {
				return libraryError(r, "InvalidData", "")
			}
		}
		t, err := time.Parse(time.RFC3339Nano, value)
		if err != nil || t.UTC().Year() < 1 || t.UTC().Year() > 9999 {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, libraryTimestamp{t.UTC()})
	})
	libraryAdd("time", "format_timestamp", "String", []LibraryParam{p("value", "Timestamp")}, func(_ *Execution, _ string, a []Value) Value {
		return a[0].(libraryTimestamp).t.UTC().Format(time.RFC3339Nano)
	})
	libraryAdd("time", "unix_seconds", "Int", []LibraryParam{p("value", "Timestamp")}, func(_ *Execution, _ string, a []Value) Value { return a[0].(libraryTimestamp).t.Unix() })
	libraryAdd("time", "nanoseconds", "Int", []LibraryParam{p("value", "Timestamp")}, func(_ *Execution, _ string, a []Value) Value { return int64(a[0].(libraryTimestamp).t.Nanosecond()) })
	libraryAdd("time", "shift", libraryResult("Timestamp"), []LibraryParam{p("value", "Timestamp"), p("duration", "Duration")}, func(_ *Execution, r string, a []Value) Value {
		t := a[0].(libraryTimestamp).t.Add(time.Duration(a[1].(Duration)))
		if t.UTC().Year() < 1 || t.UTC().Year() > 9999 {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, libraryTimestamp{t})
	})
	libraryAdd("time", "difference", libraryResult("Duration"), []LibraryParam{p("left", "Timestamp"), p("right", "Timestamp")}, func(_ *Execution, r string, a []Value) Value {
		x, y := a[0].(libraryTimestamp).t, a[1].(libraryTimestamp).t
		d := x.Sub(y)
		if !y.Add(d).Equal(x) {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, Duration(d))
	})
}
func contextWithLibraryTimeout(ctx *Execution, timeout Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx.Context, time.Duration(timeout))
}

var libraryTimestampPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$`)
