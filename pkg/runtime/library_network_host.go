//go:build !ms_lean

package msruntime

import (
	"net/http"
	"net/url"
	"sort"
	"strings"
	"unicode/utf8"
)

func init() {
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"Network", "request", libraryResult("ClientResponse", "HttpError"), []LibraryParam{{"method", "String"}, {"url", "String"}, {"headers", "Map[String][String]"}, {"body", "Bytes"}, {"max_response_bytes", "Optional[Int]"}, {"timeout", "Optional[Duration]"}}},
		{"Network", "lookup", libraryResult("List[String]", "NetworkError"), []LibraryParam{{"name", "String"}, {"max_records", "Optional[Int]"}, {"timeout", "Optional[Duration]"}}},
	}...)
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
	if max < 0 || timeout < nativeNoTimeout {
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
	for _, e := range a[2].(*Map).Entries {
		name, value := e.Key.(string), e.Value.(string)
		if !libraryHeaderName(name) || strings.ContainsAny(value, "\r\n\x00") || strings.EqualFold(name, "Content-Length") || strings.EqualFold(name, "Transfer-Encoding") || strings.EqualFold(name, "Host") {
			return libraryError(r, "InvalidInput", "")
		}
		req.Header.Set(name, value)
	}
	// No ambient proxy or cookie jar. Redirects are returned to the caller for explicit policy decisions.
	transport := &http.Transport{TLSHandshakeTimeout: nativeTransportTimeout(timeout), MaxResponseHeaderBytes: nativeUnlimited, DisableCompression: true, DisableKeepAlives: true, DialContext: n.dial}
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
	headers := &Map{Type: "@std/Map[String][@std/List[String]]"}
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
	if max < 0 || timeout < nativeNoTimeout {
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
