import (
    Data from "@std/core.ms",
    Bytes, BytesBuilder from "@std/bytes.ms",
    HashAlgorithm,
    constant_time_equal,
    ecdsa_sign,
    ecdsa_verify,
    rsa_sign,
    rsa_verify,
    sign,
    verify from "@std/crypto.ms",
    base64_encode, base64_decode from "@std/data/encoding.ms",
    JsonValue, parse, stringify from "@std/data/json.ms",
    now from "@std/time.ms",
)

fn jwt_invalid_key() Error:
    return Error("jwt: invalid key", kind: "EINVAL")

// Selects how a token is signed. A verifier names the one it accepts; it never trusts the algorithm a token claims.
export enum JwtAlgorithm:
    // HMAC with SHA-256 and a shared secret of any length (use at least 32 random bytes).
    Hs256
    // HMAC with SHA-384 and a shared secret.
    Hs384
    // HMAC with SHA-512 and a shared secret.
    Hs512
    // RSASSA-PKCS1-v1_5 with SHA-256. Signing takes a PKCS#8 DER private key; verifying takes a PKIX DER public key.
    Rs256
    // ECDSA over P-256 with SHA-256. Signing takes a PKCS#8 DER private key; verifying takes a PKIX DER public key.
    Es256
    // Ed25519. Signing takes the 32-byte private seed; verifying takes the 32-byte public key.
    EdDsa

// What `verify_token` requires of a token beyond its signature.
export type JwtCheck:
    // The only algorithm accepted; a token whose header names another returns an Error with kind `EBADMSG`.
    algorithm: JwtAlgorithm = JwtAlgorithm.Hs256
    // When set, the `iss` claim must equal it.
    issuer: String? = none
    // When set, the `aud` claim, a string or a list of strings, must include it.
    audience: String? = none
    // Seconds of clock skew tolerated when checking `exp` and `nbf`.
    leeway: Int = 0
    // The Unix time in seconds to judge `exp` and `nbf` against; none uses the current time.
    at: Int? = none
    // The largest token in bytes accepted before any decoding; larger tokens return an Error with kind `EBADMSG`.
    max_bytes: Int = 16384

type JwtHeader:
    alg: String
    typ: String

/*
Creates a signed token from `claims`, a record or `JsonValue` object such as `Session(sub: "42", exp: 1900000000)`.
The result is the compact `header.claims.signature` form, ready for an `Authorization: Bearer` header or a cookie.
`key` is the secret for the HMAC algorithms and the private key for the others, in the form `JwtAlgorithm` describes.
Registered claims (`exp`, `iat`, `iss`, `aud`) are ordinary fields; the library does not add any. A key that does not suit the algorithm returns an Error with kind `EINVAL`.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
type Session:
    sub: String
    exp: Int

token := try sign_token(Session(sub: "42", exp: 1900000000), secret)
session := try verify_token[Session](token, secret)
```
*/
export fn sign_token[T: Data](
    claims: T,
    key: Bytes,
    algorithm: JwtAlgorithm = JwtAlgorithm.Hs256
) String!:
    header := stringify(JwtHeader(alg: algorithm_name(algorithm), typ: "JWT"))
    payload := stringify(claims)
    if header.is_error() or payload.is_error(): return error(jwt_invalid_key())

    head := base64_encode(header.get("").to_bytes(), url_safe: true, padded: false)
    body := base64_encode(payload.get("").to_bytes(), url_safe: true, padded: false)
    signing_input := "{head}.{body}"
    signature := try sign_bytes(algorithm, key, signing_input.to_bytes())
    return ok(
        "{signing_input}.{base64_encode(signature, url_safe: true, padded: false)}"
    )

/*
Checks a token's signature and claims, and returns its claims decoded as `T` (a record, or `JsonValue` for the raw object).
The signature is verified before the claims are read. `check.algorithm` is the only algorithm accepted, so a token cannot choose a weaker one or `none`.
The payload must be a JSON object; any other JSON value returns EBADMSG.
Critical header extensions and unencoded payloads are unsupported and rejected.
`exp` and `nbf` (seconds since the Unix epoch) are enforced when present; `iss` and `aud` are enforced when `check` names them.
`key` is the secret for the HMAC algorithms and the public key for the others, in the form `JwtAlgorithm` describes.
Failures return an `Error` that says which check failed; show a caller one generic message, as the specific cause helps an attacker.
*/
export fn verify_token[T: Data = JsonValue](
    token: String,
    key: Bytes,
    check: JwtCheck = JwtCheck()
) T!:
    if token.byte_length() > check.max_bytes: return error(
        Error("jwt: malformed token", kind: "EBADMSG")
    )

    parts := token.split(".")
    if parts.length() != 3: return error(Error("jwt: malformed token", kind: "EBADMSG"))

    header := try decode_json[JsonValue](parts[0], check.max_bytes)
    if not header_algorithm_matches(
        header.get("alg").get(JsonValue.Null), check.algorithm
    ): return error(Error("jwt: wrong algorithm", kind: "EBADMSG"))

    // No critical header extension is supported by this verifier.
    if header.get("crit").is_some(): return error(
        Error("jwt: unsupported critical header", kind: "EBADMSG")
    )

    if encoded := header.get("b64"):
        if not encoded.as_bool().get(false): return error(
            Error("jwt: unsupported payload encoding", kind: "EBADMSG")
        )

    signature := base64_decode(
        parts[2], url_safe: true, max_bytes: check.max_bytes, padded: false
    )
    if signature.is_error(): return error(
        Error("jwt: malformed token", kind: "EBADMSG")
    )

    signing_input := "{parts[0]}.{parts[1]}"
    genuine := try verify_bytes(
        check.algorithm, key, signing_input.to_bytes(), signature.get("".to_bytes())
    )
    if not genuine: return error(Error("jwt: bad signature", kind: "EBADMSG"))

    claims := try decode_json[JsonValue](parts[1], check.max_bytes)
    try check_claims(claims, check)
    return decode_json[T](parts[1], check.max_bytes)

fn header_algorithm_matches(value: JsonValue, algorithm: JwtAlgorithm) Bool:
    match value:
        StringValue(name): return name == algorithm_name(algorithm)
        _: return false

fn algorithm_name(algorithm: JwtAlgorithm) String:
    match algorithm:
        Hs256: return "HS256"
        Hs384: return "HS384"
        Hs512: return "HS512"
        Rs256: return "RS256"
        Es256: return "ES256"
        EdDsa: return "EdDSA"

fn decode_json[T: Data](part: String, limit: Int) T!:
    raw := base64_decode(part, url_safe: true, max_bytes: limit, padded: false)
    if raw.is_error(): return error(Error("jwt: malformed token", kind: "EBADMSG"))

    text := raw.get("".to_bytes()).decode_utf8()
    if text.is_none(): return error(Error("jwt: malformed token", kind: "EBADMSG"))

    value := parse[T](text.get(""))
    if decoded := value: return ok(decoded)

    return error(Error("jwt: malformed token", kind: "EBADMSG"))

fn hmac_hash(algorithm: JwtAlgorithm) HashAlgorithm?:
    match algorithm:
        Hs256: return HashAlgorithm.Sha256
        Hs384: return HashAlgorithm.Sha384
        Hs512: return HashAlgorithm.Sha512
        _: return none

fn sign_bytes(algorithm: JwtAlgorithm, key: Bytes, data: Bytes) Bytes!:
    if hash := hmac_hash(algorithm):
        mac := hash.hmac(key, data)
        if bytes := mac: return ok(bytes)

        return error(jwt_invalid_key())

    if algorithm == JwtAlgorithm.Rs256:
        signed := rsa_sign(key, HashAlgorithm.Sha256, data)
        if bytes := signed: return ok(bytes)

        return error(jwt_invalid_key())

    if algorithm == JwtAlgorithm.Es256:
        signed := ecdsa_sign(key, HashAlgorithm.Sha256, data)
        if der := signed: return der_to_raw(der, 32)

        return error(jwt_invalid_key())

    signed := sign(key, data)
    if bytes := signed: return ok(bytes)

    return error(jwt_invalid_key())

fn verify_bytes(
    algorithm: JwtAlgorithm,
    key: Bytes,
    data: Bytes,
    signature: Bytes
) Bool!:
    if hash := hmac_hash(algorithm):
        mac := hash.hmac(key, data)
        if bytes := mac: return ok(constant_time_equal(bytes, signature))

        return error(jwt_invalid_key())

    if algorithm == JwtAlgorithm.Rs256:
        return ok(rsa_verify(key, HashAlgorithm.Sha256, data, signature))

    if algorithm == JwtAlgorithm.Es256:
        if signature.length() != 64: return ok(false)

        der := raw_to_der(signature)
        return ok(ecdsa_verify(key, HashAlgorithm.Sha256, data, der))

    return ok(verify(key, data, signature))

fn check_claims(claims: JsonValue, check: JwtCheck) Unit!:
    match claims:
        ObjectValue(_): unit
        _: return error(Error("jwt: claims must be an object", kind: "EBADMSG"))

    var moment = 0

    if given := check.at:
        moment = given
    else:
        moment = now().seconds

    if exp := claims.get("exp"):
        limit := try numeric_date(exp, "exp")
        if limit + check.leeway.to_float() <= moment.to_float(): return error(
            Error("jwt: token expired", kind: "EBADMSG")
        )

    if nbf := claims.get("nbf"):
        start := try numeric_date(nbf, "nbf")
        if start - check.leeway.to_float() > moment.to_float(): return error(
            Error("jwt: token not yet valid", kind: "EBADMSG")
        )

    if issuer := check.issuer:
        actual := claims.get("iss").get(JsonValue.Null).as_string()
        if actual.is_none() or actual.get("") != issuer: return error(
            Error("jwt: wrong issuer", kind: "EBADMSG")
        )

    if aud := claims.get("aud"):
        if aud.as_string().is_none():
            if many := aud.as_list():
                if many.any(fn item: item.as_string().is_none()): return error(
                    Error(
                        "jwt: aud must hold only strings", kind: "EBADMSG"
                    )
                )
            else:
                return error(
                    Error(
                        "jwt: aud must be a string or a list of strings",
                        kind: "EBADMSG"
                    )
                )

    if audience := check.audience:
        if not includes_audience(claims.get("aud").get(JsonValue.Null), audience): return error(
            Error("jwt: wrong audience", kind: "EBADMSG")
        )

// A present `exp` or `nbf` is a JSON number (RFC 7519 NumericDate); anything else is malformed.
fn numeric_date(claim: JsonValue, name: String) Float!:
    if value := claim.as_float(): return ok(value)

    return error(Error("jwt: {name} must be a number", kind: "EBADMSG"))

fn includes_audience(claim: JsonValue, audience: String) Bool:
    if single := claim.as_string(): return single == audience
    if many := claim.as_list():
        return many.any(fn item: item.as_string().get("") == audience)

    return false

// Converts an ASN.1 DER ECDSA signature to the fixed-width `r || s` form JWS uses.
fn der_to_raw(der: Bytes, width: Int) Bytes!:
    if der.length() < 8 or der.get(0).to_int() != 48: return error(jwt_invalid_key())

    var at = 2
    if der.get(1).to_int() >= 128: at = 3

    var out = BytesBuilder()

    for side in 0..2:
        if at + 2 > der.length() or der.get(at).to_int() != 2: return error(
            jwt_invalid_key()
        )

        var size = der.get(at + 1).to_int()
        var start = at + 2
        if start + size > der.length() or size > width + 1: return error(
            jwt_invalid_key()
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

// Converts a fixed-width `r || s` signature to ASN.1 DER.
fn raw_to_der(raw: Bytes) Bytes:
    half := raw.length() / 2
    var body = BytesBuilder()

    for piece in 0..2:
        var start = piece * half
        while start < (piece + 1) * half - 1 and raw.get(start).to_int() == 0:
            start += 1

        var size = (piece + 1) * half - start
        pad := raw.get(start).to_int() >= 128
        if pad: size += 1
        body.append(2)
        body.append(size.to_uint8().get(0))
        if pad: body.append(0)
        for place in start..((piece + 1) * half):
            body.append(raw.get(place))

    inner := body.build()
    var out = BytesBuilder()
    out.append(48)
    if inner.length() >= 128: out.append(129)
    out.append(inner.length().to_uint8().get(0))
    out.append_bytes(inner)
    return out.build()
