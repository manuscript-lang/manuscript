// conform: tags=stdlib-net,tier-stdlib,testing
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import headers from "@std/net/http.ms"
import parse from "@std/net/url.ms"
import (
    check_redirect,
    is_domain_or_subdomain,
    redirect_headers,
    redirect_keeps_body,
    redirect_method,
    referer_for from "@std/net/redirect.ms",
)

test "redirect statuses pick the follow-up method":
    expect_equal(redirect_method(301, "POST"), "GET")?
    expect_equal(redirect_method(303, "HEAD"), "HEAD")?
    expect_equal(redirect_method(307, "POST"), "POST")?
    expect_equal(redirect_method(200, "GET"), none)?
    expect_true(redirect_keeps_body(308))?
    expect_false(redirect_keeps_body(302))?

test "redirect limits":
    http := parse("http://a.test/")?
    https := parse("https://a.test/")?
    expect_true(check_redirect(0, http, https, true, max_redirects: 1).is_ok())?
    expect_true(check_redirect(1, http, https, true, max_redirects: 1).is_error())?
    expect_true(check_redirect(5, http, https, true).is_ok())?
    expect_true(check_redirect(0, https, http, true).is_error())?
    expect_true(check_redirect(0, http, https, false).is_error())?

test "subdomains and ip literals":
    expect_true(is_domain_or_subdomain("www.Example.com", "example.com"))?
    expect_false(is_domain_or_subdomain("badexample.com", "example.com"))?
    expect_false(is_domain_or_subdomain("1.2.3.4", "3.4"))?
    expect_true(is_domain_or_subdomain("1.2.3.4", "1.2.3.4"))?

test "referer":
    a := parse("https://a.test/x?token=1")?
    same := parse("https://a.test/y")?
    other := parse("https://b.test/")?
    down := parse("http://a.test/")?
    var set = headers()
    set.append("Referer", "https://given.test/")?
    expect_equal(referer_for(a, same, headers(), "https://a.test/x?token=1"), "https://a.test/x?token=1")?
    expect_equal(referer_for(a, other, headers(), "https://a.test/x?token=1"), none)?
    expect_equal(referer_for(a, down, set, "https://a.test/x?token=1"), none)?
    expect_equal(referer_for(a, other, set, "https://a.test/x?token=1"), "https://given.test/")?

test "headers that must not follow a redirect":
    var initial = headers()
    initial.append("Authorization", "secret")?
    initial.append("Content-Type", "text/plain")?
    initial.append("X-Keep", "1")?
    initial.append("X-Keep", "2")?
    old := parse("https://a.test/")?
    same := parse("https://a.test/next")?
    foreign := parse("https://b.test/")?
    kept := redirect_headers(initial, old, old, same, false)?
    expect_equal(kept.names(), ["Authorization", "X-Keep"])?
    expect_equal(kept.get_all("X-Keep"), ["1", "2"])?
    moved := redirect_headers(initial, old, old, foreign, true)?
    expect_equal(moved.names(), ["Content-Type", "X-Keep"])?
