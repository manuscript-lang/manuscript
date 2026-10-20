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

# Formats a version as `major.minor.patch[-prerelease][+build]`.
export fn format(version: Version) String:

# Parses strict Semantic Versioning 2.0.0 text. A leading `v` and surrounding space are rejected.
export fn parse(text: String) Result[Version, SemverError]:

impl Error for SemverError:
    # Returns a semver-prefixed diagnostic without echoing the input text.
    fn message() String:
