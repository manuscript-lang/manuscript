package msruntime

import (
	"net/http"
	"net/url"
	"path"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// HttpHeaders is an ordered multimap of header names to byte values. Names
// compare with ASCII case folding and keep the spelling of their first use.
// Each name's value list is shared membership: reading headers does not copy
// it.
type HttpHeaders struct {
	entries []headerEntry
	index   map[string]*List[*Bytes]
}

type headerEntry struct {
	name   string
	values *List[*Bytes]
}

func (h *HttpHeaders) lookup(name string) (*List[*Bytes], bool) {
	values, ok := h.index[headerKey(name)]
	return values, ok
}

func (h *HttpHeaders) add(name string, value *Bytes) {
	key := headerKey(name)
	values, ok := h.index[key]
	if !ok {
		if h.index == nil {
			h.index = map[string]*List[*Bytes]{}
		}
		values = NewList[*Bytes]()
		h.index[key] = values
		h.entries = append(h.entries, headerEntry{name, values})
	}
	values.Items = append(values.Items, value)
}

// Http_Headers returns an empty header collection.
func Http_Headers(_ *Execution) *HttpHeaders { return &HttpHeaders{} }

// HttpHeaders_Append adds a value under name; the name must be a token.
func HttpHeaders_Append(_ *Execution, h *HttpHeaders, name string, value *Bytes) Result[Unit, HttpError] {
	if !validHeaderName(name) {
		return httpFail[Unit](errHTTPInvalidInput)
	}
	h.add(name, value)
	return Ok[Unit, HttpError](Unit{})
}

// HttpHeaders_Values returns the shared value list of name, or none.
func HttpHeaders_Values(_ *Execution, h *HttpHeaders, name string) Option[*List[*Bytes]] {
	values, present := h.lookup(name)
	if !present {
		return None[*List[*Bytes]]()
	}
	return Some(values)
}

// HttpHeaders_Text returns the values of name as UTF-8 text.
func HttpHeaders_Text(ctx *Execution, h *HttpHeaders, name string) Result[Option[*List[string]], HttpError] {
	values, present := h.lookup(name)
	if !present {
		return Ok[Option[*List[string]], HttpError](None[*List[string]]())
	}
	out := NewList[string]()
	for _, value := range values.Items {
		CheckCancelled(ctx)
		if !utf8.Valid(value.Data) {
			return httpFail[Option[*List[string]]](errHTTPInvalidData)
		}
		out.Items = append(out.Items, string(value.Data))
	}
	return Ok[Option[*List[string]], HttpError](Some(out))
}

// HttpHeaders_Names returns each distinct name in first-use order.
func HttpHeaders_Names(_ *Execution, h *HttpHeaders) *List[string] {
	out := NewList[string]()
	for _, entry := range h.entries {
		out.Items = append(out.Items, entry.name)
	}
	return out
}

// HttpHeaders_Clone returns an independent collection with copied value lists.
func HttpHeaders_Clone(ctx *Execution, h *HttpHeaders) *HttpHeaders {
	CheckCancelled(ctx)
	out := &HttpHeaders{index: map[string]*List[*Bytes]{}}
	for _, entry := range h.entries {
		values := NewList(append([]*Bytes(nil), entry.values.Items...)...)
		out.entries = append(out.entries, headerEntry{entry.name, values})
		out.index[headerKey(entry.name)] = values
	}
	return out
}

// HttpHeaders_Remove deletes name and reports whether it was present.
func HttpHeaders_Remove(_ *Execution, h *HttpHeaders, name string) bool {
	key := headerKey(name)
	if _, present := h.index[key]; !present {
		return false
	}
	delete(h.index, key)
	for i, entry := range h.entries {
		if headerKey(entry.name) == key {
			copy(h.entries[i:], h.entries[i+1:])
			last := len(h.entries) - 1
			h.entries[last] = headerEntry{}
			h.entries = h.entries[:last]
			break
		}
	}
	return true
}

// ClientResponse_Metadata returns the status and headers of a buffered response.
func ClientResponse_Metadata(_ *Execution, r *ClientResponse) *HttpResponseMetadata { return r.Head }

// HttpMethod_Text returns the method token.
func HttpMethod_Text(_ *Execution, m HttpMethod) string { return methodToken(m) }

func methodToken(m HttpMethod) string {
	switch m := m.(type) {
	case HttpMethod_Get:
		return "GET"
	case HttpMethod_Head:
		return "HEAD"
	case HttpMethod_Post:
		return "POST"
	case HttpMethod_Put:
		return "PUT"
	case HttpMethod_Patch:
		return "PATCH"
	case HttpMethod_Delete:
		return "DELETE"
	case HttpMethod_Connect:
		return "CONNECT"
	case HttpMethod_Options:
		return "OPTIONS"
	case HttpMethod_Trace:
		return "TRACE"
	case HttpMethod_Custom:
		return m.Value
	}
	return ""
}

func methodOf(token string) HttpMethod {
	switch token {
	case "GET":
		return HttpMethod_Get{}
	case "HEAD":
		return HttpMethod_Head{}
	case "POST":
		return HttpMethod_Post{}
	case "PUT":
		return HttpMethod_Put{}
	case "PATCH":
		return HttpMethod_Patch{}
	case "DELETE":
		return HttpMethod_Delete{}
	case "CONNECT":
		return HttpMethod_Connect{}
	case "OPTIONS":
		return HttpMethod_Options{}
	case "TRACE":
		return HttpMethod_Trace{}
	}
	return HttpMethod_Custom{Value: token}
}

func validHeaderName(name string) bool {
	if name == "" {
		return false
	}
	for _, r := range name {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("!#$%&'*+-.^_`|~", r)) {
			return false
		}
	}
	return true
}

// Source header values are UTF-8 text. HTTP permits HTAB, visible bytes and
// non-ASCII text, but no other control bytes or DEL.
func validHeaderValue(value string) bool {
	if !utf8.ValidString(value) {
		return false
	}
	for i := range len(value) {
		if value[i] < 32 && value[i] != '\t' || value[i] == 127 {
			return false
		}
	}
	return true
}

// headerKey folds ASCII case; HTTP field names are not Unicode-folded.
func headerKey(name string) string {
	for i := range len(name) {
		if name[i] >= 'A' && name[i] <= 'Z' {
			data := []byte(name)
			for j := i; j < len(data); j++ {
				if data[j] >= 'A' && data[j] <= 'Z' {
					data[j] += 'a' - 'A'
				}
			}
			return string(data)
		}
	}
	return name
}

// headersFrom converts net/http headers, sorted by name.
func headersFrom(headers http.Header) *HttpHeaders {
	out := &HttpHeaders{}
	names := make([]string, 0, len(headers))
	for name := range headers {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, key := range names {
		for _, value := range headers[key] {
			out.add(key, NewBytes([]byte(value)))
		}
		if len(headers[key]) == 0 {
			out.add(key, nil)
			values, _ := out.lookup(key)
			values.Items = values.Items[:0]
		}
	}
	return out
}

// textHeaders reports whether every received name and value is UTF-8.
func textHeaders(headers http.Header) bool {
	for key, values := range headers {
		if !utf8.ValidString(key) {
			return false
		}
		for _, value := range values {
			if !utf8.ValidString(value) {
				return false
			}
		}
	}
	return true
}

// requestHeaders returns the request headers including Host, which net/http
// moves out of Header into Request.Host.
func requestHeaders(r *http.Request) http.Header {
	headers := r.Header.Clone()
	if headers == nil {
		headers = http.Header{}
	}
	if r.Host != "" {
		headers.Set("Host", r.Host)
	}
	return headers
}

// normalizeRequestPath makes the decoded path safe to route on: an encoded
// slash or NUL is rejected, and dot segments (including encoded ones) are
// resolved so no spelling can climb above the root.
func normalizeRequestPath(r *http.Request) bool {
	raw := r.URL.EscapedPath()
	if strings.Contains(raw, "%00") || strings.Contains(strings.ToLower(raw), "%2f") || strings.Contains(r.URL.Path, "\x00") {
		return false
	}
	if strings.HasPrefix(r.URL.Path, "/") {
		clean := path.Clean(r.URL.Path)
		if strings.HasSuffix(r.URL.Path, "/") && clean != "/" {
			clean += "/"
		}
		r.URL.Path, r.URL.RawPath = clean, ""
	}
	return true
}

func validPort(u *url.URL) bool {
	port := u.Port()
	if port == "" {
		return true
	}
	n, err := strconv.Atoi(port)
	return err == nil && n <= 65535
}

func sameOrigin(a, b *url.URL) bool {
	return strings.EqualFold(a.Scheme, b.Scheme) && strings.EqualFold(a.Host, b.Host)
}

// outgoingHeaders copies caller headers into req, rejecting names the
// transport manages. It reports false for any malformed field.
func outgoingHeaders(dst http.Header, src *HttpHeaders, managed ...string) bool {
	for _, entry := range src.entries {
		if !validHeaderName(entry.name) {
			return false
		}
		for _, m := range managed {
			if strings.EqualFold(entry.name, m) {
				return false
			}
		}
		for _, item := range entry.values.Items {
			value := string(item.Data)
			if !validHeaderValue(value) {
				return false
			}
			dst.Add(entry.name, value)
		}
	}
	return true
}
