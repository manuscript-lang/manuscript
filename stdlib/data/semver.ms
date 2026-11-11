// A parsed semantic version as defined by Semantic Versioning 2.0.0.
export type Version:
	// Major version number; incremented for incompatible changes.
	major: Int
	// Minor version number; incremented for compatible additions.
	minor: Int
	// Patch version number; incremented for compatible fixes.
	patch: Int
	// Dot-separated pre-release identifiers in input order; empty for a release version.
	prerelease: List[String] = []
	// Dot-separated build metadata identifiers in input order; ignored by compare.
	build: List[String] = []

// Compares two versions by SemVer precedence, returning -1, 0 or 1.
// Build metadata is ignored, and a pre-release sorts before its release.
fn Version.compare(other: Version) Int:
	core := compare_ints(self.major, other.major)
	if core != 0: return core

	minor := compare_ints(self.minor, other.minor)
	if minor != 0: return minor

	patch := compare_ints(self.patch, other.patch)
	if patch != 0: return patch
	if self.prerelease.is_empty() and other.prerelease.is_empty(): return 0
	if self.prerelease.is_empty(): return 1
	if other.prerelease.is_empty(): return -1

	shared := compare_ints(self.prerelease.length(), other.prerelease.length())
	limit := self.prerelease.length()
	other_length := other.prerelease.length()
	count := if other_length < limit: other_length else: limit

	for index in 0..count:
		order := compare_identifier(self.prerelease[index], other.prerelease[index])
		if order != 0: return order

	return shared

// Formats a version as `major.minor.patch[-prerelease][+build]`.
fn Version.format() String:
	var text = "{self.major}.{self.minor}.{self.patch}"
	if not self.prerelease.is_empty(): text = "{text}-{self.prerelease.join(".")}"
	if not self.build.is_empty(): text = "{text}+{self.build.join(".")}"
	return text

// Parses strict Semantic Versioning 2.0.0 text. A leading `v` and surrounding space are rejected.
export fn parse(text: String) Version!:
	build_parts := split_first(text, "+")
	core_and_pre := split_first(build_parts[0].clone(), "-")
	numbers := core_and_pre[0].split(".")
	if numbers.length() != 3: return error(
		Error("semver: invalid data", kind: "EBADMSG")
	)

	var values = List[Int]()
	var out_of_range = false

	for part in numbers:
		scalars := part.scalar_values()
		if not all_digits(scalars.clone()) or has_leading_zero(scalars): return error(
			Error("semver: invalid data", kind: "EBADMSG")
		)

		if value := part.parse_int(): values.append(value)
		else:
			out_of_range = true
			values.append(0)

	var prerelease = List[String]()

	if core_and_pre.length() == 2:
		for identifier in core_and_pre[1].split("."):
			scalars := identifier.scalar_values()
			if not valid_identifier(scalars.clone()): return error(
				Error("semver: invalid data", kind: "EBADMSG")
			)
			if all_digits(scalars.clone()) and has_leading_zero(scalars): return error(
				Error("semver: invalid data", kind: "EBADMSG")
			)

			prerelease.append(identifier)

	var build = List[String]()

	if build_parts.length() == 2:
		for identifier in build_parts[1].split("."):
			if not valid_identifier(identifier.scalar_values()): return error(
				Error("semver: invalid data", kind: "EBADMSG")
			)

			build.append(identifier)

	if out_of_range: return error(Error("semver: value out of range", kind: "ERANGE"))

	return ok(
		Version(
			major: values[0], minor: values[1], patch: values[2],
			prerelease: prerelease, build: build
		)
	)

// Splits at the first separator only; `String.split` with a part cap drops the rest instead of keeping it.
fn split_first(text: String, separator: String) List[String]:
	if at := text.index_of(separator): return [text.take(at), text.drop(at + 1)]
	return [text.clone()]

fn compare_ints(left: Int, right: Int) Int:
	if left < right: return -1
	if left > right: return 1

	return 0

// Digits only, at least one; the caller has already rejected non-ASCII through scalar values.
fn all_digits(scalars: List[Int]) Bool:
	if scalars.is_empty(): return false

	for scalar in scalars:
		if scalar < 48 or scalar > 57: return false
	return true

fn has_leading_zero(scalars: List[Int]) Bool:
	return scalars.length() > 1 and scalars[0] == 48

// ASCII letters, digits and hyphen, at least one.
fn valid_identifier(scalars: List[Int]) Bool:
	if scalars.is_empty(): return false

	for scalar in scalars:
		digit := scalar >= 48 and scalar <= 57
		upper := scalar >= 65 and scalar <= 90
		lower := scalar >= 97 and scalar <= 122
		if not (digit or upper or lower or scalar == 45): return false

	return true

// Numeric identifiers sort numerically and before alphanumeric ones; others sort bytewise.
fn compare_identifier(left: String, right: String) Int:
	left_numeric := all_digits(left.scalar_values())
	right_numeric := all_digits(right.scalar_values())

	if left_numeric and right_numeric:
		by_length := compare_ints(left.length(), right.length())
		if by_length != 0: return by_length

		return left.compare(right)

	if left_numeric: return -1
	if right_numeric: return 1

	return left.compare(right)
