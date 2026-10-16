package msruntime

import (
	"io"
	"net"
	"net/url"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Url_EncodeComponent percent-encodes one URL component using UTF-8 bytes.
func Url_EncodeComponent(_ *Execution, text string) string {
	var b strings.Builder
	const digits = "0123456789ABCDEF"
	for i := 0; i < len(text); i++ {
		v := text[i]
		if v >= 'A' && v <= 'Z' || v >= 'a' && v <= 'z' || v >= '0' && v <= '9' || strings.ContainsRune("-._~", rune(v)) {
			b.WriteByte(v)
		} else {
			b.WriteByte('%')
			b.WriteByte(digits[v>>4])
			b.WriteByte(digits[v&15])
		}
	}
	return b.String()
}

// Url_DecodeComponent decodes one percent-encoded component; `+` stays a plus.
func Url_DecodeComponent(_ *Execution, text string) Result[string, UrlError] {
	s, err := url.PathUnescape(text)
	if err != nil || !utf8.ValidString(s) {
		return Fail[string, UrlError](UrlError_InvalidData{})
	}
	return Ok[string, UrlError](s)
}

// Url_Parse parses an absolute URL into its components.
func Url_Parse(_ *Execution, text string) Result[*Url, UrlError] {
	u, err := url.Parse(text)
	if err != nil || u.Scheme == "" || u.User != nil {
		return Fail[*Url, UrlError](UrlError_InvalidData{})
	}
	return urlValue(u)
}

// Url_Resolve resolves a relative reference against a base URL.
func Url_Resolve(_ *Execution, base *Url, reference string) Result[*Url, UrlError] {
	b, err := goURL(base)
	if err != nil {
		return Fail[*Url, UrlError](UrlError_InvalidInput{})
	}
	u, err := url.Parse(reference)
	if err != nil || u.User != nil {
		return Fail[*Url, UrlError](UrlError_InvalidData{})
	}
	return urlValue(b.ResolveReference(u))
}

// Url_Format formats URL components as an absolute or relative URL.
func Url_Format(_ *Execution, value *Url) Result[string, UrlError] {
	u, err := goURL(value)
	if err != nil {
		return Fail[string, UrlError](UrlError_InvalidInput{})
	}
	return Ok[string, UrlError](u.String())
}

// Url_ParseQuery parses a query string, preserving duplicate keys and order.
func Url_ParseQuery(ctx *Execution, text string, maxEntries Option[int]) Result[*List[*QueryEntry], UrlError] {
	limit, ok := optLimit(maxEntries, netUnlimited)
	if !ok {
		return Fail[*List[*QueryEntry], UrlError](UrlError_InvalidInput{})
	}
	items := []*QueryEntry{}
	if text != "" {
		for _, part := range strings.Split(text, "&") {
			CheckCancelled(ctx)
			if part == "" {
				continue
			}
			if len(items) >= limit {
				return Fail[*List[*QueryEntry], UrlError](UrlError_LimitExceeded{})
			}
			k, v, _ := strings.Cut(part, "=")
			k, e1 := url.QueryUnescape(k)
			v, e2 := url.QueryUnescape(v)
			if e1 != nil || e2 != nil || !utf8.ValidString(k) || !utf8.ValidString(v) {
				return Fail[*List[*QueryEntry], UrlError](UrlError_InvalidData{})
			}
			items = append(items, &QueryEntry{Key: k, Value: v})
		}
	}
	return Ok[*List[*QueryEntry], UrlError](NewList(items...))
}

// Url_FormatQuery encodes query entries as a query string.
func Url_FormatQuery(_ *Execution, entries *List[*QueryEntry]) string {
	parts := make([]string, len(entries.Items))
	for i, e := range entries.Items {
		parts[i] = url.QueryEscape(e.Key) + "=" + url.QueryEscape(e.Value)
	}
	return strings.Join(parts, "&")
}

func urlValue(u *url.URL) Result[*Url, UrlError] {
	port := Option[int]{}
	if u.User != nil || u.Opaque != "" || u.Scheme == "" {
		return Fail[*Url, UrlError](UrlError_InvalidData{})
	}
	if s := u.Port(); s != "" {
		n, err := strconv.ParseInt(s, 10, 64)
		if err != nil || n < 0 || n > 65535 {
			return Fail[*Url, UrlError](UrlError_InvalidData{})
		}
		port = Some(int(n))
	}
	if !utf8.ValidString(u.Path) || !utf8.ValidString(u.Fragment) {
		return Fail[*Url, UrlError](UrlError_InvalidData{})
	}
	return Ok[*Url, UrlError](&Url{Scheme: strings.ToLower(u.Scheme), Host: strings.ToLower(u.Hostname()), Port: port, Path: u.EscapedPath(), Query: u.RawQuery, Fragment: u.Fragment})
}

func goURL(v *Url) (*url.URL, error) {
	host := v.Host
	if strings.Contains(host, ":") {
		host = "[" + host + "]"
	}
	if v.Port.Some {
		n := v.Port.Val
		if n < 0 || n > 65535 {
			return nil, io.ErrUnexpectedEOF
		}
		host = net.JoinHostPort(v.Host, strconv.Itoa(n))
	}
	raw := v.Path
	decoded, err := url.PathUnescape(raw)
	if err != nil || !utf8.ValidString(decoded) {
		return nil, io.ErrUnexpectedEOF
	}
	if !validURLQuery(v.Query) || strings.ContainsAny(host, " <>\"") {
		return nil, io.ErrUnexpectedEOF
	}
	u := &url.URL{Scheme: v.Scheme, Host: host, Path: decoded, RawPath: raw, RawQuery: v.Query, Fragment: v.Fragment}
	parsed, err := url.Parse(u.String())
	if err != nil || parsed.Scheme == "" || parsed.User != nil || strings.ContainsAny(host, "/@\\\r\n") {
		return nil, io.ErrUnexpectedEOF
	}
	return u, nil
}

// validURLQuery rejects query text that would not round-trip through parse: a
// '#' starts the fragment, spaces and controls are not allowed raw, and '%'
// must begin a two-digit escape.
func validURLQuery(query string) bool {
	for i := 0; i < len(query); i++ {
		c := query[i]
		switch {
		case c == '#' || c == ' ' || c < 0x20 || c == 0x7f:
			return false
		case c == '%':
			if i+2 >= len(query) || !isHexDigit(query[i+1]) || !isHexDigit(query[i+2]) {
				return false
			}
		}
	}
	return true
}

func isHexDigit(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
}
