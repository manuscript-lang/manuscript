package msruntime

import (
	"net/http/httptest"
	"testing"
)

func TestNormalizeHTTPRequestPath(t *testing.T) {
	for target, want := range map[string]string{
		"/a/b":         "/a/b",
		"/a%20b":       "/a b",
		"/a/../b":      "/b",
		"/%2e%2e/x":    "/x",
		"/a/./b/":      "/a/b/",
		"/../../etc":   "/etc",
		"/x?y=%2F":     "/x",
		"/files/a%2Fb": "",
		"/files/a%2fb": "",
		"/a%00b":       "",
	} {
		r := httptest.NewRequest("GET", target, nil)
		ok := normalizeHTTPRequestPath(r)
		if want == "" {
			if ok {
				t.Errorf("%s accepted as %q", target, r.URL.Path)
			}
		} else if !ok || r.URL.Path != want {
			t.Errorf("%s: got %q %v, want %q", target, r.URL.Path, ok, want)
		}
	}
}
