package main

import (
	"strconv"
	"strings"

	rt "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// idsText encodes identifiers as `[x..,x..]`.
func idsText(ids []string) string {
	hs := make([]string, len(ids))
	for i, id := range ids {
		hs[i] = h(id)
	}
	return "[" + strings.Join(hs, ",") + "]"
}

func versionText(v *rt.Version) string {
	return strings.Join([]string{strconv.Itoa(v.Major), strconv.Itoa(v.Minor), strconv.Itoa(v.Patch), idsText(v.Prerelease.Items), idsText(v.Build.Items)}, " ")
}

func genSemver(dir string) {
	r := &recorder{}
	alpha := []string{"0", "1", "2", "9", "10", ".", ".", "-", "+", "a", "B", "rc", "x", "_", " ", "v", "é", "00", "01", "18446744073709551616", "9223372036854775807", "9223372036854775808"}
	inputs := append([]string{"", "1", "1.2", "1.2.3", "1.2.3.4", "0.0.0", "01.2.3", "1.02.3", "1.2.03", "1.2.3-", "1.2.3+", "1.2.3-a", "1.2.3-a.b", "1.2.3-a..b", "1.2.3-01", "1.2.3-0", "1.2.3-a01", "1.2.3-1a", "1.2.3+01", "1.2.3+a.b-c", "1.2.3-a+b", "1.2.3-a-b+c-d", "1.2.3+b+c", "v1.2.3", " 1.2.3", "1.2.3 ", "1.2.3-é", "9223372036854775807.0.0", "9223372036854775808.0.0", "1.99999999999999999999.3-x", "1.99999999999999999999.03", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.0+build", "1.0.0-0.3.7", "1.0.0-x.7.z.92", "1.0.0-x-y-z.-", "1.0.0--", "1.0.0-123456789012345678901234567890", "1.0.0-123456789012345678901234567891", "-1.0.0", "1.-1.0", "+1.0.0"},
		randomStrings(7, 400, 10, alpha)...)
	var valid []*rt.Version
	for _, in := range inputs {
		res := rt.Semver_Parse(nil, in)
		if res.Failed {
			r.row("parse", h(in), "=>", "err", errName(res.Err))
			continue
		}
		r.row("parse", h(in), "=>", "ok", versionText(res.Val))
		r.row("format", versionText(res.Val), "=>", h(rt.Semver_Format(nil, res.Val)))
		valid = append(valid, res.Val)
	}
	if len(valid) > 120 {
		valid = valid[:120]
	}
	for _, a := range valid {
		for _, b := range valid {
			r.row("compare", versionText(a), versionText(b), "=>", strconv.Itoa(rt.Semver_Compare(nil, a, b)))
		}
	}
	// Hand-built records may hold values that parse rejects (negative numbers, leading zeros, empty ids).
	mk := func(ma, mi, pa int, pre, build []string) *rt.Version {
		return &rt.Version{Major: ma, Minor: mi, Patch: pa, Prerelease: rt.NewList(pre...), Build: rt.NewList(build...)}
	}
	built := []*rt.Version{
		mk(-1, 0, 0, nil, nil), mk(0, -5, 2, nil, nil), mk(1, 2, 3, []string{"01"}, nil), mk(1, 2, 3, []string{"1"}, nil),
		mk(1, 2, 3, []string{""}, nil), mk(1, 2, 3, []string{"a", ""}, []string{""}), mk(1, 2, 3, []string{"a"}, []string{"b", "c"}),
		mk(1, 2, 3, []string{"00", "0"}, nil), mk(1, 2, 3, []string{"é"}, nil), mk(1, 2, 3, []string{"Z"}, nil), mk(1, 2, 3, []string{"a"}, nil),
		mk(9223372036854775807, 0, 0, nil, nil), mk(-9223372036854775808, 0, 0, nil, nil),
	}
	for _, a := range built {
		r.row("format", versionText(a), "=>", h(rt.Semver_Format(nil, a)))
		for _, b := range built {
			r.row("compare", versionText(a), versionText(b), "=>", strconv.Itoa(rt.Semver_Compare(nil, a, b)))
		}
	}
	r.write(dir, "semver.tsv")
}
