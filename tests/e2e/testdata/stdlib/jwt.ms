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
    secret := "your-256-bit-secret".to_bytes()
    claims := Profile(sub: "1234567890", name: "John Doe", iat: 1516239022)
    token := (sign_token(claims, secret) | try expect_ok)
    token | try expect_equal(
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    )

    back := (verify_token[Profile](token, secret) | try expect_ok)
    back.name | try expect_equal("John Doe")
    back.iat | try expect_equal(1516239022)

test "hs384 and hs512 match independent implementations":
    secret := "secret".to_bytes()
    claims := session(1900000000)
    (sign_token(claims, secret, JwtAlgorithm.Hs384) | try expect_ok) | try expect_equal(
        "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.T0nuVj4bcMcyxFsFJy-slqWjCzwA4nXs7yyOuxg3pfL01lWUyI2hcJinI6AxZIYW"
    )
    (sign_token(claims, secret, JwtAlgorithm.Hs512) | try expect_ok) | try expect_equal(
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.l7ZljlzTyputKNz9OPWJnsqWHe6ypJYHzFT_KgHlG83kxZaLOq2cxM3mM6ipWAiUZXz-Y6XYuGm4IGE64bruOw"
    )

test "verify returns the claims as a record or as a JSON document":
    secret := "secret".to_bytes()
    token := (sign_token(session(1900000000), secret) | try expect_ok)
    typed := (verify_token[Session](token, secret) | try expect_ok)
    typed.iss | try expect_equal("me")

    raw := (verify_token(token, secret) | try expect_ok)
    raw.get("sub").get(JsonValue.Null).as_string().get("") | try expect_equal("42")

test "verify rejects a wrong key, a tampered body and a different algorithm":
    secret := "secret".to_bytes()
    token := (sign_token(session(1900000000), secret) | try expect_ok)
    (try failure(verify_token[Session](token, "other".to_bytes()))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

    parts := token.split(".")
    forged := (
        sign_token(
            Session(sub: "1", exp: 1900000000, iss: "me"), secret
        ) | try expect_ok
    )
    swapped := "{parts[0]}.{forged.split(".")[1]}.{parts[2]}"
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
    secret := "secret".to_bytes()

    // {"alg":"none"} . {"sub":"42","exp":1900000000,"iss":"me"} . (empty signature)
    unsigned := "eyJhbGciOiJub25lIn0.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ."
    (try failure(verify_token[Session](unsigned, secret))) | try expect_equal(
        Error("jwt: wrong algorithm", kind: "EBADMSG")
    )
    for text in ["", "a.b", "a.b.c.d", "...", "!!!.???.***"]:
        (try failure(verify_token[Session](text, secret))) | try expect_equal(
            Error("jwt: malformed token", kind: "EBADMSG")
        )

    big := "a".repeat(20000).get("")
    (try failure(verify_token[Session](big, secret))) | try expect_equal(
        Error("jwt: malformed token", kind: "EBADMSG")
    )

test "verify enforces exp, nbf, iss and aud":
    secret := "secret".to_bytes()
    stamp := (sign_token(session(1000), secret) | try expect_ok)
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

    doc := (verify_token(stamp, secret, JwtCheck(at: 5)) | try expect_ok)
    doc.get("exp").get(JsonValue.Null).as_int().get(0) | try expect_equal(1000)

type Timed:
    nbf: Int
    aud: List[String]

type Audience:
    aud: String

test "verify checks nbf and audience claims":
    secret := "secret".to_bytes()
    later := (sign_token(Timed(nbf: 100, aud: ["a", "b"]), secret) | try expect_ok)
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

    single := (sign_token(Audience(aud: "a"), secret) | try expect_ok)
    (verify_token[Audience](single, secret, JwtCheck(audience: "a")) | try expect_ok).aud | try expect_equal(
        "a"
    )
    (try failure(verify_token[Audience](single, secret, JwtCheck(audience: "b")))) | try expect_equal(
        Error("jwt: wrong audience", kind: "EBADMSG")
    )

test "verify rejects registered claims of the wrong type":
    secret := "secret".to_bytes()
    wrong := Error("jwt: nbf must be a number", kind: "EBADMSG")
    cases := [
        "\{\"nbf\":\"tomorrow\"\}", "\{\"nbf\":null\}", "\{\"exp\":\"never\"\}",
        "\{\"exp\":[1]\}", "\{\"aud\":[123]\}", "\{\"aud\":[123,\"wanted\"]\}",
        "\{\"aud\":7\}"
    ]

    for text in cases:
        claims := (parse(text) | try expect_ok)
        token := (sign_token(claims, secret) | try expect_ok)
        outcome := verify_token(token, secret, JwtCheck(at: 100, audience: "wanted"))
        try expect_equal(outcome.err().kind, "EBADMSG")

    nbf := (
        sign_token(
            (parse("\{\"nbf\":\"tomorrow\"\}") | try expect_ok), secret
        ) | try expect_ok
    )
    (try failure(verify_token(nbf, secret, JwtCheck(at: 100)))) | try expect_equal(
        wrong
    )

    fine := (
        sign_token(
            (parse("\{\"aud\":[\"wanted\"],\"exp\":200\}") | try expect_ok), secret
        ) | try expect_ok
    )
    _ := (
        verify_token(
            fine, secret, JwtCheck(at: 100, audience: "wanted")
        ) | try expect_ok
    )

// Independently generated HS256 JWS tokens with key "secret" and the exact JSON
// payloads in order: null, false, true, 42, "claims", "{\"exp\":0}", [], [{"exp":0}].
// Their signatures are genuine; it is the JWT claim-set shape that is invalid.
test "verify rejects signed payloads that are not claim objects":
    secret := "secret".to_bytes()
    tokens := [
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bnVsbA.7DWrkJHEM03NP-M-9zlpZJ3Ud49InV9BpM_GlfnVpfM",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ZmFsc2U.v3xsRo_HK_XvkswA16frrfBQP810JGE38bD4NqsS_5E",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dHJ1ZQ.u6JbcRO2MvlKSxPEklUhzTqMgOhc0bdhamtvrpXOGUg",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.NDI.DpSBf8asYLjZ8f-FNmbOgcAqnUgtEhVlF7yfz6fkGEo",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ImNsYWltcyI.V5GvU8jhwxwzZ9nJ4aymJBVAnzeKPYcsd96uYSci4j4",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.IntcImV4cFwiOjB9Ig.6TGcWjV1CR-ExDygwsohJL4beyAkhp3ua8afG5OraNE",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.W10.ny0W7Pkele2S9JjQz1pcPuE-7_Jrt2VBqPEO1UnPyQg",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.W3siZXhwIjowfV0.9JxJ3QGSMH2Ey3kNrUVwlUusIl_VcEEMKXanDqU_piI"
    ]
    for token in tokens:
        (try failure(verify_token(token, secret, JwtCheck(at: 100)))) | try expect_equal(
            Error("jwt: claims must be an object", kind: "EBADMSG")
        )

test "claim object validation applies before typed payload decoding":
    secret := "secret".to_bytes()
    null_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bnVsbA.7DWrkJHEM03NP-M-9zlpZJ3Ud49InV9BpM_GlfnVpfM"
    number_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.NDI.DpSBf8asYLjZ8f-FNmbOgcAqnUgtEhVlF7yfz6fkGEo"
    array_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.W10.ny0W7Pkele2S9JjQz1pcPuE-7_Jrt2VBqPEO1UnPyQg"
    invalid := Error("jwt: claims must be an object", kind: "EBADMSG")
    (try failure(verify_token[Int?](null_token, secret))) | try expect_equal(invalid)
    (try failure(verify_token[Int](number_token, secret))) | try expect_equal(invalid)
    (try failure(verify_token[List[Int]](array_token, secret))) | try expect_equal(
        invalid
    )

test "claim object validation follows signature verification":
    token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bnVsbA.7DWrkJHEM03NP-M-9zlpZJ3Ud49InV9BpM_GlfnVpfM"
    (try failure(verify_token(token, "other".to_bytes()))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

test "verify accepts empty claim objects and nested values":
    secret := "secret".to_bytes()
    empty := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-IDcSemACt8x4iTMCda8Yhe3iZaWbvV5XKSTbuAn0M"
    nested := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuZXN0ZWQiOltdLCJhY3RpdmUiOnRydWV9.mgN1ikVmpILfLmGzXL3xy4bWgwTvpDt52bslkrtkIjM"
    claims := (verify_token(empty, secret) | try expect_ok)
    try expect_true(claims.as_map().is_some())
    claims.as_map().get().length() | try expect_equal(0)

    rich := (verify_token(nested, secret) | try expect_ok)
    rich.get("active").get().as_bool().get() | try expect_equal(true)
    rich.get("nested").get().as_list().get().length() | try expect_equal(0)

test "rs256 signs with a private key and verifies with the public key":
    private := (rsa_generate(2048) | try expect_ok)
    public := (public_key_der(private) | try expect_ok)
    token := (
        sign_token(
            session(1900000000), private, JwtAlgorithm.Rs256
        ) | try expect_ok
    )
    check := JwtCheck(algorithm: JwtAlgorithm.Rs256)
    (verify_token[Session](token, public, check) | try expect_ok).sub | try expect_equal(
        "42"
    )

    other := (public_key_der((rsa_generate(2048) | try expect_ok)) | try expect_ok)
    (try failure(verify_token[Session](token, other, check))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

test "es256 signatures are raw 64 bytes and verify":
    private := (ecdsa_generate(Curve.P256) | try expect_ok)
    public := (public_key_der(private) | try expect_ok)
    check := JwtCheck(algorithm: JwtAlgorithm.Es256)

    for round in 0..20:
        token := (
            sign_token(
                session(1900000000 + round), private, JwtAlgorithm.Es256
            ) | try expect_ok
        )
        token.split(".")[2].length() | try expect_equal(86)
        (verify_token[Session](token, public, check) | try expect_ok).exp | try expect_equal(
            1900000000 + round
        )

    token := (sign_token(session(1), private, JwtAlgorithm.Es256) | try expect_ok)
    other := (
        public_key_der(
            (ecdsa_generate(Curve.P256) | try expect_ok)
        ) | try expect_ok
    )
    (try failure(verify_token[Session](token, other, check))) | try expect_equal(
        Error("jwt: bad signature", kind: "EBADMSG")
    )

test "eddsa signs with a seed and verifies with the public key":
    seed := (random_bytes(32) | try expect_ok)
    public := (public_key(seed) | try expect_ok)
    check := JwtCheck(algorithm: JwtAlgorithm.EdDsa)
    token := (
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
    result := sign_token(session(1), "short".to_bytes(), JwtAlgorithm.EdDsa)
    if _ := result: return fail("accepted")

    result | try expect_equal(error(Error("jwt: invalid key", kind: "EINVAL")))
