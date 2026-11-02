import Data from "@std/core.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import (
    HashAlgorithm,
    constant_time_equal,
    ecdsa_sign,
    ecdsa_verify,
    rsa_sign,
    rsa_verify,
    sign,
    verify
) from "@std/crypto.ms"
import base64_encode_unpadded, base64_decode_unpadded from "@std/data/encoding.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"
import now from "@std/os/time.ms"

# Selects how a token is signed. A verifier names the one it accepts; it never trusts the algorithm a token claims.
export type JwtAlgorithm:
    # HMAC with SHA-256 and a shared secret of any length (use at least 32 random bytes).
    case Hs256
    # HMAC with SHA-384 and a shared secret.
    case Hs384
    # HMAC with SHA-512 and a shared secret.
    case Hs512
    # RSASSA-PKCS1-v1_5 with SHA-256. Signing takes a PKCS#8 DER private key; verifying takes a PKIX DER public key.
    case Rs256
    # ECDSA over P-256 with SHA-256. Signing takes a PKCS#8 DER private key; verifying takes a PKIX DER public key.
    case Es256
    # Ed25519. Signing takes the 32-byte private seed; verifying takes the 32-byte public key.
    case EdDsa

# Errors returned when signing or verifying a token.
export type JwtError:
    # The key does not suit the algorithm, or `claims` cannot be written as a JSON object.
    case InvalidKey
    # The token is oversized, is not three Base64url parts, or its header or claims are not valid JSON of the expected shape.
    case Malformed
    # The token's header names a different algorithm than the one the verifier accepts, including `none`.
    case WrongAlgorithm
    # The signature does not match the header and claims under the key.
    case BadSignature
    # The `exp` claim is at or before the current time, allowing for the leeway.
    case Expired
    # The `nbf` claim is after the current time, allowing for the leeway.
    case NotYetValid
    # The `iss` claim is missing or differs from the expected issuer.
    case WrongIssuer
    # The `aud` claim is missing or does not include the expected audience.
    case WrongAudience

impl Error for JwtError:
    # Returns a fixed `jwt:`-prefixed diagnostic that never echoes the token or key.
    fn message() String:
        match self:
            InvalidKey: return "jwt: invalid key"
            Malformed: return "jwt: malformed token"
            WrongAlgorithm: return "jwt: wrong algorithm"
            BadSignature: return "jwt: bad signature"
            Expired: return "jwt: token expired"
            NotYetValid: return "jwt: token not yet valid"
            WrongIssuer: return "jwt: wrong issuer"
            WrongAudience: return "jwt: wrong audience"

# What `verify_token` requires of a token beyond its signature.
export type JwtCheck:
    # The only algorithm accepted; a token whose header names another returns WrongAlgorithm.
    algorithm: JwtAlgorithm = JwtAlgorithm.Hs256
    # When set, the `iss` claim must equal it.
    issuer: String? = none
    # When set, the `aud` claim, a string or a list of strings, must include it.
    audience: String? = none
    # Seconds of clock skew tolerated when checking `exp` and `nbf`.
    leeway: Int = 0
    # The Unix time in seconds to judge `exp` and `nbf` against; none uses the current time.
    at: Int? = none
    # The largest token in bytes accepted before any decoding; larger tokens return Malformed.
    max_bytes: Int = 16384

type JwtHeader:
    alg: String
    typ: String

# Creates a signed token from `claims`, a record or `JsonValue` object such as `Session(sub: "42", exp: 1900000000)`.
# The result is the compact `header.claims.signature` form, ready for an `Authorization: Bearer` header or a cookie.
# `key` is the secret for the HMAC algorithms and the private key for the others, in the form `JwtAlgorithm` describes.
# Registered claims (`exp`, `iat`, `iss`, `aud`) are ordinary fields; the library does not add any. A key that does not suit the algorithm returns InvalidKey.
#
# ```manuscript
# type Session:
#     sub: String
#     exp: Int
#
# let token = sign_token(Session(sub: "42", exp: 1900000000), secret).get_or_fault()
# let session = verify_token[Session](token, secret).get_or_fault()
# ```
export fn sign_token[T: Data](
    claims: T,
    key: Bytes,
    algorithm: JwtAlgorithm = JwtAlgorithm.Hs256
) String!JwtError:
    let header = stringify(
        value: JwtHeader(alg: algorithm_name(algorithm), typ: "JWT"), max_bytes: none,
        indent: none
    )
    let payload = stringify(value: claims, max_bytes: none, indent: none)
    if header.is_error() or payload.is_error(): return error(JwtError.InvalidKey)

    let head = base64_encode_unpadded(header.get("").to_bytes(), url_safe: true)
    let body = base64_encode_unpadded(payload.get("").to_bytes(), url_safe: true)
    let signing_input = "{head}.{body}"
    let signature = try sign_bytes(algorithm, key, signing_input.to_bytes())
    return ok("{signing_input}.{base64_encode_unpadded(signature, url_safe: true)}")

# Checks a token's signature and claims, and returns its claims decoded as `T` (a record, or `JsonValue` for the raw object).
# The signature is verified before the claims are read. `check.algorithm` is the only algorithm accepted, so a token cannot choose a weaker one or `none`.
# `exp` and `nbf` (seconds since the Unix epoch) are enforced when present; `iss` and `aud` are enforced when `check` names them.
# `key` is the secret for the HMAC algorithms and the public key for the others, in the form `JwtAlgorithm` describes.
# Failures return a `JwtError` that says which check failed; show a caller one generic message, as the specific cause helps an attacker.
export fn verify_token[T: Data = JsonValue](
    token: String,
    key: Bytes,
    check: JwtCheck = JwtCheck()
) T!JwtError:
    if token.byte_length() > check.max_bytes: return error(JwtError.Malformed)

    let parts = token.split(".")
    if parts.length() != 3: return error(JwtError.Malformed)

    let header = try decode_json[JsonValue](parts[0], check.max_bytes)
    let name = header.get("alg").get(JsonValue.Null).as_string().get("")
    if name != algorithm_name(check.algorithm): return error(JwtError.WrongAlgorithm)

    let signature = base64_decode_unpadded(
        parts[2], url_safe: true, max_bytes: check.max_bytes
    )
    if signature.is_error(): return error(JwtError.Malformed)

    let signing_input = "{parts[0]}.{parts[1]}"
    let genuine = try verify_bytes(
        check.algorithm, key, signing_input.to_bytes(), signature.get("".to_bytes())
    )
    if not genuine: return error(JwtError.BadSignature)

    let claims = try decode_json[JsonValue](parts[1], check.max_bytes)
    try check_claims(claims, check)
    return decode_json[T](parts[1], check.max_bytes)

fn algorithm_name(algorithm: JwtAlgorithm) String:
    match algorithm:
        Hs256: return "HS256"
        Hs384: return "HS384"
        Hs512: return "HS512"
        Rs256: return "RS256"
        Es256: return "ES256"
        EdDsa: return "EdDSA"

fn decode_json[T: Data](part: String, limit: Int) T!JwtError:
    let raw = base64_decode_unpadded(part, url_safe: true, max_bytes: limit)
    if raw.is_error(): return error(JwtError.Malformed)

    let text = raw.get("".to_bytes()).decode_utf8()
    if text.is_none(): return error(JwtError.Malformed)

    let value = parse[T](text.get(""), limits: none)
    if let decoded = value:
        return ok(decoded)

    return error(JwtError.Malformed)

fn hmac_hash(algorithm: JwtAlgorithm) HashAlgorithm?:
    match algorithm:
        Hs256: return HashAlgorithm.Sha256
        Hs384: return HashAlgorithm.Sha384
        Hs512: return HashAlgorithm.Sha512
        _: return none

fn sign_bytes(algorithm: JwtAlgorithm, key: Bytes, data: Bytes) Bytes!JwtError:
    if let hash = hmac_hash(algorithm):
        let mac = hash.hmac(key, data)
        if let bytes = mac: return ok(bytes)

        return error(JwtError.InvalidKey)

    if algorithm == JwtAlgorithm.Rs256:
        let signed = rsa_sign(key, HashAlgorithm.Sha256, data)
        if let bytes = signed: return ok(bytes)

        return error(JwtError.InvalidKey)

    if algorithm == JwtAlgorithm.Es256:
        let signed = ecdsa_sign(key, HashAlgorithm.Sha256, data)
        if let der = signed: return der_to_raw(der, 32)

        return error(JwtError.InvalidKey)

    let signed = sign(key, data)
    if let bytes = signed: return ok(bytes)

    return error(JwtError.InvalidKey)

fn verify_bytes(
    algorithm: JwtAlgorithm,
    key: Bytes,
    data: Bytes,
    signature: Bytes
) Bool!JwtError:
    if let hash = hmac_hash(algorithm):
        let mac = hash.hmac(key, data)
        if let bytes = mac: return ok(constant_time_equal(bytes, signature))

        return error(JwtError.InvalidKey)

    if algorithm == JwtAlgorithm.Rs256:
        return ok(rsa_verify(key, HashAlgorithm.Sha256, data, signature))

    if algorithm == JwtAlgorithm.Es256:
        if signature.length() != 64: return ok(false)

        let der = raw_to_der(signature)
        return ok(ecdsa_verify(key, HashAlgorithm.Sha256, data, der))

    return ok(verify(key, data, signature))

fn check_claims(claims: JsonValue, check: JwtCheck) Unit!JwtError:
    var moment = 0

    if let given = check.at:
        moment = given
    else:
        moment = now().seconds

    if let exp = claims.get("exp"):
        let limit = exp.as_float().get(0.0)
        if limit + check.leeway.to_float() <= moment.to_float(): return error(
            JwtError.Expired
        )

    if let nbf = claims.get("nbf"):
        let start = nbf.as_float().get(0.0)
        if start - check.leeway.to_float() > moment.to_float(): return error(
            JwtError.NotYetValid
        )

    if let issuer = check.issuer:
        let actual = claims.get("iss").get(JsonValue.Null).as_string()
        if actual.is_none() or actual.get("") != issuer: return error(
            JwtError.WrongIssuer
        )

    if let audience = check.audience:
        if not includes_audience(claims.get("aud").get(JsonValue.Null), audience): return error(
            JwtError.WrongAudience
        )
    return ok(unit)

fn includes_audience(claim: JsonValue, audience: String) Bool:
    if let single = claim.as_string():
        return single == audience
    if let many = claim.as_list():
        return many.any(fn item: item.as_string().get("") == audience)

    return false

# Converts an ASN.1 DER ECDSA signature to the fixed-width `r || s` form JWS uses.
fn der_to_raw(der: Bytes, width: Int) Bytes!JwtError:
    if der.length() < 8 or der.get(0).to_int() != 48: return error(JwtError.InvalidKey)

    var at = 2
    if der.get(1).to_int() >= 128: at = 3

    var out = BytesBuilder()

    for side in 0..2:
        if at + 2 > der.length() or der.get(at).to_int() != 2: return error(
            JwtError.InvalidKey
        )

        var size = der.get(at + 1).to_int()
        var start = at + 2
        if start + size > der.length() or size > width + 1: return error(
            JwtError.InvalidKey
        )

        while size > width:
            start += 1
            size -= 1

        for fill in 0..(width - size):
            out.append(0)
        for place in 0..size:
            out.append(der.get(start + place))
        at = at + 2 + der.get(at + 1).to_int()

    return ok(out.build())

# Converts a fixed-width `r || s` signature to ASN.1 DER.
fn raw_to_der(raw: Bytes) Bytes:
    let half = raw.length() / 2
    var body = BytesBuilder()

    for piece in 0..2:
        var start = piece * half
        while start < (piece + 1) * half - 1 and raw.get(start).to_int() == 0:
            start += 1

        var size = (piece + 1) * half - start
        let pad = raw.get(start).to_int() >= 128
        if pad: size += 1
        body.append(2)
        body.append(size.to_uint8().get(0))
        if pad: body.append(0)
        for place in start..((piece + 1) * half):
            body.append(raw.get(place))

    let inner = body.build()
    var out = BytesBuilder()
    out.append(48)
    if inner.length() >= 128: out.append(129)
    out.append(inner.length().to_uint8().get(0))
    out.append_bytes(inner)
    return out.build()
