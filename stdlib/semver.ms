# Errors returned for malformed Semantic Versioning 2.0.0 text.
export type SemverError:
    # The text is not a valid semantic version, such as a missing component, leading zero or empty identifier.
    case InvalidData
    # A numeric component is well formed but does not fit in Int.
    case OutOfRange

# A parsed semantic version as defined by Semantic Versioning 2.0.0.
export type Version:
    # Major version number; incremented for incompatible changes.
    major: Int
    # Minor version number; incremented for compatible additions.
    minor: Int
    # Patch version number; incremented for compatible fixes.
    patch: Int
    # Dot-separated pre-release identifiers in input order; empty for a release version.
    prerelease: List[String] = []
    # Dot-separated build metadata identifiers in input order; ignored by compare.
    build: List[String] = []

# Compares two versions by SemVer precedence, returning -1, 0 or 1.
# Build metadata is ignored, and a pre-release sorts before its release.
export fn compare(left: Version, right: Version) Int:
    let core = compare_ints(left.major, right.major)
    if core != 0: return core

    let minor = compare_ints(left.minor, right.minor)
    if minor != 0: return minor

    let patch = compare_ints(left.patch, right.patch)
    if patch != 0: return patch
    if left.prerelease.is_empty() and right.prerelease.is_empty(): return 0
    if left.prerelease.is_empty(): return 1
    if right.prerelease.is_empty(): return -1

    var index = 0
    let shared = compare_ints(left.prerelease.length(), right.prerelease.length())
    let limit = left.prerelease.length()
    let other = right.prerelease.length()
    var count = limit
    if other < limit: count = other

    while index < count:
        let order = compare_identifier(left.prerelease[index], right.prerelease[index])
        if order != 0: return order

        index += 1

    return shared

# Formats a version as `major.minor.patch[-prerelease][+build]`.
export fn format(version: Version) String:
    var text = "{version.major}.{version.minor}.{version.patch}"
    if not version.prerelease.is_empty(): text = "{text}-{version.prerelease.join(".")}"
    if not version.build.is_empty(): text = "{text}+{version.build.join(".")}"
    return text

# Parses strict Semantic Versioning 2.0.0 text. A leading `v` and surrounding space are rejected.
export fn parse(text: String) Result[Version, SemverError]:
    let build_parts = text.split("+", 2)
    let core_and_pre = build_parts[0].split("-", 2)
    let numbers = core_and_pre[0].split(".")
    if numbers.length() != 3: return error(SemverError.InvalidData)

    var values = List[Int]()
    var out_of_range = false

    for part in numbers:
        let scalars = part.scalar_values()
        if not all_digits(scalars.clone()) or has_leading_zero(scalars): return error(
            SemverError.InvalidData
        )

        if let value = part.parse_int(): values.append(value)
        else:
            out_of_range = true
            values.append(0)

    var prerelease = List[String]()

    if core_and_pre.length() == 2:
        for identifier in core_and_pre[1].split("."):
            let scalars = identifier.scalar_values()
            if not valid_identifier(scalars.clone()): return error(SemverError.InvalidData)
            if all_digits(scalars.clone()) and has_leading_zero(scalars): return error(
                SemverError.InvalidData
            )

            prerelease.append(identifier)

    var build = List[String]()

    if build_parts.length() == 2:
        for identifier in build_parts[1].split("."):
            if not valid_identifier(identifier.scalar_values()): return error(
                SemverError.InvalidData
            )

            build.append(identifier)

    if out_of_range: return error(SemverError.OutOfRange)

    return ok(
        Version(
            major: values[0], minor: values[1], patch: values[2],
            prerelease: prerelease, build: build
        )
    )

fn compare_ints(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

# Digits only, at least one; the caller has already rejected non-ASCII through scalar values.
fn all_digits(scalars: List[Int]) Bool:
    if scalars.is_empty(): return false

    for scalar in scalars:
        if scalar < 48 or scalar > 57: return false
    return true

fn has_leading_zero(scalars: List[Int]) Bool:
    return scalars.length() > 1 and scalars[0] == 48

# ASCII letters, digits and hyphen, at least one.
fn valid_identifier(scalars: List[Int]) Bool:
    if scalars.is_empty(): return false

    for scalar in scalars:
        let digit = scalar >= 48 and scalar <= 57
        let upper = scalar >= 65 and scalar <= 90
        let lower = scalar >= 97 and scalar <= 122
        if not (digit or upper or lower or scalar == 45): return false

    return true

# Numeric identifiers sort numerically and before alphanumeric ones; others sort bytewise.
fn compare_identifier(left: String, right: String) Int:
    let left_numeric = all_digits(left.scalar_values())
    let right_numeric = all_digits(right.scalar_values())

    if left_numeric and right_numeric:
        let by_length = compare_ints(left.length(), right.length())
        if by_length != 0: return by_length

        return left.compare(right)

    if left_numeric: return -1
    if right_numeric: return 1

    return left.compare(right)

impl Error for SemverError:
    # Returns a semver-prefixed diagnostic without echoing the input text.
    fn message() String:
        match self:
            InvalidData: return "semver: invalid data"
            OutOfRange: return "semver: value out of range"
