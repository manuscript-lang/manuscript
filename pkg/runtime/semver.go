package msruntime

import (
	"strconv"
	"strings"
)

func semverFail(e SemverError) Result[*Version, SemverError] { return Fail[*Version, SemverError](e) }

func Errors_Message_SemverError(_ *Execution, e SemverError) string {
	switch e.(type) {
	case SemverError_InvalidData:
		return "semver: " + txInvalidData
	case SemverError_OutOfRange:
		return "semver: " + txOutOfRange
	}
	return "semver: operation failed"
}

func Semver_Parse(_ *Execution, text string) Result[*Version, SemverError] {
	rest, build, hasBuild := strings.Cut(text, "+")
	core, pre, hasPre := strings.Cut(rest, "-")
	parts := strings.Split(core, ".")
	if len(parts) != 3 {
		return semverFail(SemverError_InvalidData{})
	}
	var numbers [3]int
	outOfRange := false
	for i, part := range parts {
		if !semverNumeric(part) || (len(part) > 1 && part[0] == '0') {
			return semverFail(SemverError_InvalidData{})
		}
		n, err := strconv.ParseInt(part, 10, strconv.IntSize)
		if err != nil {
			outOfRange = true
			continue
		}
		numbers[i] = int(n)
	}
	var preIDs, buildIDs []string
	if hasPre {
		preIDs = strings.Split(pre, ".")
		for _, id := range preIDs {
			if !semverIdentifier(id) || (semverNumeric(id) && len(id) > 1 && id[0] == '0') {
				return semverFail(SemverError_InvalidData{})
			}
		}
	}
	if hasBuild {
		buildIDs = strings.Split(build, ".")
		for _, id := range buildIDs {
			if !semverIdentifier(id) {
				return semverFail(SemverError_InvalidData{})
			}
		}
	}
	if outOfRange {
		return semverFail(SemverError_OutOfRange{})
	}
	return Ok[*Version, SemverError](&Version{
		Major:      numbers[0],
		Minor:      numbers[1],
		Patch:      numbers[2],
		Prerelease: NewList(preIDs...),
		Build:      NewList(buildIDs...),
	})
}

func Semver_Format(_ *Execution, v *Version) string {
	var b strings.Builder
	b.WriteString(strconv.Itoa(v.Major) + "." + strconv.Itoa(v.Minor) + "." + strconv.Itoa(v.Patch))
	if len(v.Prerelease.Items) > 0 {
		b.WriteString("-" + strings.Join(v.Prerelease.Items, "."))
	}
	if len(v.Build.Items) > 0 {
		b.WriteString("+" + strings.Join(v.Build.Items, "."))
	}
	return b.String()
}

func Semver_Compare(_ *Execution, left, right *Version) int {
	for _, pair := range [3][2]int{{left.Major, right.Major}, {left.Minor, right.Minor}, {left.Patch, right.Patch}} {
		if pair[0] != pair[1] {
			return semverSign(pair[0] < pair[1])
		}
	}
	l, r := left.Prerelease.Items, right.Prerelease.Items
	switch {
	case len(l) == 0 && len(r) == 0:
		return 0
	case len(l) == 0:
		return 1
	case len(r) == 0:
		return -1
	}
	for i := 0; i < len(l) && i < len(r); i++ {
		if c := semverCompareIdentifier(l[i], r[i]); c != 0 {
			return c
		}
	}
	switch {
	case len(l) < len(r):
		return -1
	case len(l) > len(r):
		return 1
	}
	return 0
}

func semverCompareIdentifier(a, b string) int {
	an, bn := semverNumeric(a), semverNumeric(b)
	switch {
	case an && bn:
		// Equal-length digit strings without leading zeros compare lexically,
		// so identifiers beyond Int need no parsing.
		if len(a) != len(b) {
			return semverSign(len(a) < len(b))
		}
		return strings.Compare(a, b)
	case an:
		return -1
	case bn:
		return 1
	}
	return strings.Compare(a, b)
}

func semverSign(less bool) int {
	if less {
		return -1
	}
	return 1
}

func semverNumeric(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func semverIdentifier(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '-') {
			return false
		}
	}
	return true
}
