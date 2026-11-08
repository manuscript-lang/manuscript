import expect_equal, expect_ok, expect_true, fail from "@std/test/test.ms"
import Bytes from "@std/bytes.ms"
import (
    ecdsa_generate,
    public_key_der,
    rsa_generate,
    public_key,
    Curve
) from "@std/crypto.ms"
import JsonValue, parse from "@std/data/json.ms"
import (sign_token, verify_token, JwtAlgorithm, JwtCheck) from "@std/data/jwt.ms"
import random_bytes from "@std/random.ms"

type Profile:
    sub: String
    name: String
    iat: Int

type Session:
    sub: String
    exp: Int
    iss: String

fn failure[T](result: T!) Error!:
    match result:
        ok(_): return error(Error("accepted"))
        error(cause): return ok(cause)

fn session(exp: Int) Session:
    return Session(sub: "42", exp: exp, iss: "me")

test "hs256 matches the published token":
    let secret = "your-256-bit-secret".to_bytes()
    let claims = Profile(sub: "1234567890", name: "John Doe", iat: 1516239022)
    let token = (sign_token(claims, secret) | try expect_ok)
    token | try expect_equal(
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    )

    let back = (verify_token[Profile](token, secret) | try expect_ok)
    back.name | try expect_equal("John Doe")
    back.iat | try expect_equal(1516239022)

test "hs384 and hs512 match independent implementations":
    let secret = "secret".to_bytes()
    let claims = session(1900000000)
    (sign_token(claims, secret, JwtAlgorithm.Hs384) | try expect_ok) | try expect_equal(
        "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.T0nuVj4bcMcyxFsFJy-slqWjCzwA4nXs7yyOuxg3pfL01lWUyI2hcJinI6AxZIYW"
    )
    (sign_token(claims, secret, JwtAlgorithm.Hs512) | try expect_ok) | try expect_equal(
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.l7ZljlzTyputKNz9OPWJnsqWHe6ypJYHzFT_KgHlG83kxZaLOq2cxM3mM6ipWAiUZXz-Y6XYuGm4IGE64bruOw"
    )

test "verify returns the claims as a record or as a JSON document":
    let secret = "secret".to_bytes()
    let token = (sign_token(session(1900000000), secret) | try expect_ok)
    let typed = (verify_token[Session](token, secret) | try expect_ok)
    typed.iss | try expect_equal("me")

    let raw = (verify_token(token, secret) | try expect_ok)
    raw.get("sub").get(JsonValue.Null).as_string().get("") | try expect_equal("42")

test "verify rejects a wrong key, a tampered body and a different algorithm":
    let secret = "secret".to_bytes()
    let token = (sign_token(session(1900000000), secret) | try expect_ok)
    (try failure(verify_token[Session](token, "other".to_bytes()))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

    let parts = token.split(".")
    let forged = (
        sign_token(
            Session(sub: "1", exp: 1900000000, iss: "me"), secret
        ) | try expect_ok
    )
    let swapped = "{parts[0]}.{forged.split(".")[1]}.{parts[2]}"
    (try failure(verify_token[Session](swapped, secret))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )
    (
        try failure(
            verify_token[Session](
                token, secret, JwtCheck(algorithm: JwtAlgorithm.Hs512)
            )
        )
    ) | try expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))

test "verify rejects the none algorithm and malformed tokens":
    let secret = "secret".to_bytes()

    // {"alg":"none"} . {"sub":"42","exp":1900000000,"iss":"me"} . (empty signature)
    let unsigned = "eyJhbGciOiJub25lIn0.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ."
    (try failure(verify_token[Session](unsigned, secret))) | try expect_equal(
        Error("jwt: wrong algorithm", kind: "EBADMSG")
    )
    for text in ["", "a.b", "a.b.c.d", "...", "!!!.???.***"]:
        (try failure(verify_token[Session](text, secret))) | try expect_equal(
            Error("jwt: malformed token", kind: "EBADMSG")
        )

    let big = "a".repeat(20000).get("")
    (try failure(verify_token[Session](big, secret))) | try expect_equal(
        Error("jwt: malformed token", kind: "EBADMSG")
    )

test "verify enforces exp, nbf, iss and aud":
    let secret = "secret".to_bytes()
    let stamp = (sign_token(session(1000), secret) | try expect_ok)
    (verify_token[Session](stamp, secret, JwtCheck(at: 999)) | try expect_ok).sub | try expect_equal(
        "42"
    )
    (try failure(verify_token[Session](stamp, secret, JwtCheck(at: 1000)))) | try expect_equal(
        Error("jwt: token expired", kind: "EBADMSG")
    )
    (
        verify_token[Session](
            stamp, secret, JwtCheck(at: 1005, leeway: 10)
        ) | try expect_ok
    ).sub | try expect_equal("42")
    (
        verify_token[Session](
            stamp, secret, JwtCheck(at: 5, issuer: "me")
        ) | try expect_ok
    ).sub | try expect_equal("42")
    (try failure(verify_token[Session](stamp, secret, JwtCheck(at: 5, issuer: "you")))) | try expect_equal(
        Error("jwt: wrong issuer", kind: "EBADMSG")
    )

    let doc = (verify_token(stamp, secret, JwtCheck(at: 5)) | try expect_ok)
    doc.get("exp").get(JsonValue.Null).as_int().get(0) | try expect_equal(1000)

type Timed:
    nbf: Int
    aud: List[String]

type Audience:
    aud: String

test "verify checks nbf and audience claims":
    let secret = "secret".to_bytes()
    let later = (sign_token(Timed(nbf: 100, aud: ["a", "b"]), secret) | try expect_ok)
    (try failure(verify_token[Timed](later, secret, JwtCheck(at: 50)))) | try expect_equal(
        Error("jwt: token not yet valid", kind: "EBADMSG")
    )
    (
        verify_token[Timed](
            later, secret, JwtCheck(at: 100, audience: "b")
        ) | try expect_ok
    ).nbf | try expect_equal(100)
    (try failure(verify_token[Timed](later, secret, JwtCheck(at: 100, audience: "c")))) | try expect_equal(
        Error("jwt: wrong audience", kind: "EBADMSG")
    )

    let single = (sign_token(Audience(aud: "a"), secret) | try expect_ok)
    (verify_token[Audience](single, secret, JwtCheck(audience: "a")) | try expect_ok).aud | try expect_equal(
        "a"
    )
    (try failure(verify_token[Audience](single, secret, JwtCheck(audience: "b")))) | try expect_equal(
        Error("jwt: wrong audience", kind: "EBADMSG")
    )

test "verify rejects registered claims of the wrong type":
    let secret = "secret".to_bytes()
    let wrong = Error("jwt: nbf must be a number", kind: "EBADMSG")
    let cases = [
        "\{\"nbf\":\"tomorrow\"\}", "\{\"nbf\":null\}", "\{\"exp\":\"never\"\}",
        "\{\"exp\":[1]\}", "\{\"aud\":[123]\}", "\{\"aud\":[123,\"wanted\"]\}",
        "\{\"aud\":7\}"
    ]

    for text in cases:
        let claims = (parse(text) | try expect_ok)
        let token = (sign_token(claims, secret) | try expect_ok)
        let outcome = verify_token(token, secret, JwtCheck(at: 100, audience: "wanted"))
        try expect_equal(outcome.err().kind, "EBADMSG")

    let nbf = (
        sign_token(
            (parse("\{\"nbf\":\"tomorrow\"\}") | try expect_ok), secret
        ) | try expect_ok
    )
    (try failure(verify_token(nbf, secret, JwtCheck(at: 100)))) | try expect_equal(
        wrong
    )

    let fine = (
        sign_token(
            (parse("\{\"aud\":[\"wanted\"],\"exp\":200\}") | try expect_ok), secret
        ) | try expect_ok
    )
    let _ = (
        verify_token(
            fine, secret, JwtCheck(at: 100, audience: "wanted")
        ) | try expect_ok
    )

test "rs256 signs with a private key and verifies with the public key":
    let private = (rsa_generate(2048) | try expect_ok)
    let public = (public_key_der(private) | try expect_ok)
    let token = (
        sign_token(
            session(1900000000), private, JwtAlgorithm.Rs256
        ) | try expect_ok
    )
    let check = JwtCheck(algorithm: JwtAlgorithm.Rs256)
    (verify_token[Session](token, public, check) | try expect_ok).sub | try expect_equal(
        "42"
    )

    let other = (public_key_der((rsa_generate(2048) | try expect_ok)) | try expect_ok)
    (try failure(verify_token[Session](token, other, check))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

test "es256 signatures are raw 64 bytes and verify":
    let private = (ecdsa_generate(Curve.P256) | try expect_ok)
    let public = (public_key_der(private) | try expect_ok)
    let check = JwtCheck(algorithm: JwtAlgorithm.Es256)

    for round in 0..20:
        let token = (
            sign_token(
                session(1900000000 + round), private, JwtAlgorithm.Es256
            ) | try expect_ok
        )
        token.split(".")[2].length() | try expect_equal(86)
        (verify_token[Session](token, public, check) | try expect_ok).exp | try expect_equal(
            1900000000 + round
        )

    let token = (sign_token(session(1), private, JwtAlgorithm.Es256) | try expect_ok)
    let other = (
        public_key_der(
            (ecdsa_generate(Curve.P256) | try expect_ok)
        ) | try expect_ok
    )
    (try failure(verify_token[Session](token, other, check))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

test "eddsa signs with a seed and verifies with the public key":
    let seed = (random_bytes(32) | try expect_ok)
    let public = (public_key(seed) | try expect_ok)
    let check = JwtCheck(algorithm: JwtAlgorithm.EdDsa)
    let token = (
        sign_token(
            session(1900000000), seed, JwtAlgorithm.EdDsa
        ) | try expect_ok
    )
    (verify_token[Session](token, public, check) | try expect_ok).sub | try expect_equal(
        "42"
    )
    (try failure(verify_token[Session](token, public, JwtCheck()))) | try expect_equal(
        Error("jwt: wrong algorithm", kind: "EBADMSG")
    )

test "sign returns InvalidKey for a key that does not fit":
    let result = sign_token(session(1), "short".to_bytes(), JwtAlgorithm.EdDsa)
    if let _ = result: return fail("accepted")

    result | try expect_equal(error(Error("jwt: invalid key", kind: "EINVAL")))
