//go:build !ms_lean

package msruntime

import (
	"net/http"
	"net/url"
	"strings"
)

func init() {
	LibraryMethods = append(LibraryMethods, []LibraryMethod{
		{"Network", "request", libraryResult("ClientResponse", "HttpError"), []LibraryParam{{"method", "HttpMethod"}, {"url", "String"}, {"headers", "HttpHeaders"}, {"body", "Bytes"}, {"max_response_bytes", "Optional[Int]"}, {"timeout", "Optional[Duration]"}}},
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
	method, address := libraryHTTPMethodText(a[0]), a[1].(string)
	if !validHeaderName(method) {
		return libraryError(r, "InvalidInput", "")
	}
	max, timeout := a[4].(int64), a[5].(Duration)
	if max < 0 || timeout < nativeNoTimeout {
		return libraryError(r, "InvalidInput", "")
	}
	u, err := url.Parse(address)
	if err != nil || u.Host == "" || u.User != nil || !libraryValidPort(u) || u.Scheme != "http" && u.Scheme != "https" {
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
	for _, entry := range a[2].(*libraryHeaders).Entries {
		name := entry.Key.(string)
		if !libraryHeaderName(name) || strings.EqualFold(name, "Content-Length") || strings.EqualFold(name, "Transfer-Encoding") || strings.EqualFold(name, "Host") {
			return libraryError(r, "InvalidInput", "")
		}
		for _, item := range entry.Value.(*List).Items {
			value := string(item.(Bytes).Items)
			if !validHeaderValue(value) {
				return libraryError(r, "InvalidInput", "")
			}
			req.Header.Add(name, value)
		}
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
	if !libraryHTTPTextHeaders(response.Header) {
		return libraryError(r, "InvalidData", "")
	}
	headers := libraryHTTPHeaders(response.Header)
	return libraryOK(r, Record{"@std/ClientResponse", map[string]Value{"status": int64(response.StatusCode), "headers": headers, "body": Bytes{data}}})
}

func libraryHeaderName(s string) bool { return validHeaderName(s) }

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
