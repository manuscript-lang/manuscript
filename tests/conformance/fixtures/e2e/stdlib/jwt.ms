// conform: tags=testing,tier-io
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	Curve,
	ecdsa_generate,
	public_key,
	public_key_der,
	rsa_generate from "@std/crypto/crypto.ms",
	JsonValue, parse from "@std/data/json.ms",
	JwtAlgorithm, JwtCheck, sign_token, verify_token from "@std/data/jwt.ms",
	random_bytes from "@std/random.ms",
	expect_equal, expect_ok, expect_true, fail from "@std/test/test.ms",
)

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
	token := (sign_token(claims, secret) | expect_ok?)
	(
		token
		| expect_equal(
			"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
		)?
	)

	back := (verify_token[Profile](token, secret) | expect_ok?)
	back.name | expect_equal("John Doe")?
	back.iat | expect_equal(1516239022)?

test "hs384 and hs512 match independent implementations":
	secret := "secret".to_bytes()
	claims := session(1900000000)
	(
		(sign_token(claims, secret, JwtAlgorithm.Hs384) | expect_ok?)
		| expect_equal(
			"eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.T0nuVj4bcMcyxFsFJy-slqWjCzwA4nXs7yyOuxg3pfL01lWUyI2hcJinI6AxZIYW"
		)?
	)
	(
		(sign_token(claims, secret, JwtAlgorithm.Hs512) | expect_ok?)
		| expect_equal(
			"eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ.l7ZljlzTyputKNz9OPWJnsqWHe6ypJYHzFT_KgHlG83kxZaLOq2cxM3mM6ipWAiUZXz-Y6XYuGm4IGE64bruOw"
		)?
	)

test "verify returns the claims as a record or as a JSON document":
	secret := "secret".to_bytes()
	token := (sign_token(session(1900000000), secret) | expect_ok?)
	typed := (verify_token[Session](token, secret) | expect_ok?)
	typed.iss | expect_equal("me")?

	raw := (verify_token(token, secret) | expect_ok?)
	raw.get("sub").get(JsonValue.Null).as_string().get("") | expect_equal("42")?

test "verify rejects a wrong key, a tampered body and a different algorithm":
	secret := "secret".to_bytes()
	token := (sign_token(session(1900000000), secret) | expect_ok?)
	(
		(
			failure(verify_token[Session](token, "other".to_bytes()))?
		) | expect_equal(Error("jwt: bad signature", kind: "EBADMSG"))?
	)

	parts := token.split(".")
	forged := (
		sign_token(
			Session(sub: "1", exp: 1900000000, iss: "me"),
			secret,
		) | expect_ok?
	)
	swapped := "{parts[0]}.{forged.split(".")[1]}.{parts[2]}"
	(
		(failure(verify_token[Session](swapped, secret))?)
		| expect_equal(Error("jwt: bad signature", kind: "EBADMSG"))?
	)
	(
		(
			failure(
				verify_token[Session](
					token,
					secret,
					JwtCheck(algorithm: JwtAlgorithm.Hs512),
				)
			)?
		) | expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))?
	)

test "verify rejects the none algorithm and malformed tokens":
	secret := "secret".to_bytes()

	// {"alg":"none"} . {"sub":"42","exp":1900000000,"iss":"me"} . (empty signature)
	unsigned := "eyJhbGciOiJub25lIn0.eyJzdWIiOiI0MiIsImV4cCI6MTkwMDAwMDAwMCwiaXNzIjoibWUifQ."
	(
		(failure(verify_token[Session](unsigned, secret))?)
		| expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))?
	)
	for text in ["", "a.b", "a.b.c.d", "...", "!!!.???.***"]:
		(
			(failure(verify_token[Session](text, secret))?)
			| expect_equal(Error("jwt: malformed token", kind: "EBADMSG"))?
		)

	big := "a".repeat(20000).get("")
	(
		(failure(verify_token[Session](big, secret))?) | expect_equal(
			Error("jwt: malformed token", kind: "EBADMSG")
		)?
	)

test "verify enforces exp, nbf, iss and aud":
	secret := "secret".to_bytes()
	stamp := (sign_token(session(1000), secret) | expect_ok?)
	(
		(
			verify_token[Session](
				stamp,
				secret,
				JwtCheck(at: 999),
			) | expect_ok?
		).sub | expect_equal("42")?
	)
	(
		(
			failure(
				verify_token[Session](stamp, secret, JwtCheck(at: 1000))
			)?
		) | expect_equal(Error("jwt: token expired", kind: "EBADMSG"))?
	)
	(
		(
			verify_token[Session](
				stamp,
				secret,
				JwtCheck(at: 1005, leeway: 10),
			) | expect_ok?
		).sub | expect_equal("42")?
	)
	(
		(
			verify_token[Session](
				stamp,
				secret,
				JwtCheck(at: 5, issuer: "me"),
			) | expect_ok?
		).sub | expect_equal("42")?
	)
	(
		(
			failure(
				verify_token[Session](
					stamp,
					secret,
					JwtCheck(at: 5, issuer: "you"),
				)
			)?
		) | expect_equal(Error("jwt: wrong issuer", kind: "EBADMSG"))?
	)

	doc := (verify_token(stamp, secret, JwtCheck(at: 5)) | expect_ok?)
	doc.get("exp").get(JsonValue.Null).as_int().get(0) | expect_equal(1000)?

type Timed:
	nbf: Int
	aud: List[String]

type Audience:
	aud: String

test "verify checks nbf and audience claims":
	secret := "secret".to_bytes()
	later := (sign_token(Timed(nbf: 100, aud: ["a", "b"]), secret) | expect_ok?)
	(
		(
			failure(verify_token[Timed](later, secret, JwtCheck(at: 50)))?
		) | expect_equal(Error("jwt: token not yet valid", kind: "EBADMSG"))?
	)
	(
		(
			verify_token[Timed](
				later,
				secret,
				JwtCheck(at: 100, audience: "b"),
			) | expect_ok?
		).nbf | expect_equal(100)?
	)
	(
		(
			failure(
				verify_token[Timed](
					later,
					secret,
					JwtCheck(at: 100, audience: "c"),
				)
			)?
		) | expect_equal(Error("jwt: wrong audience", kind: "EBADMSG"))?
	)

	single := (sign_token(Audience(aud: "a"), secret) | expect_ok?)
	(
		(
			verify_token[Audience](
				single,
				secret,
				JwtCheck(audience: "a"),
			) | expect_ok?
		).aud | expect_equal("a")?
	)
	(
		(
			failure(
				verify_token[Audience](
					single,
					secret,
					JwtCheck(audience: "b"),
				)
			)?
		) | expect_equal(Error("jwt: wrong audience", kind: "EBADMSG"))?
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
		claims := (parse(text) | expect_ok?)
		token := (sign_token(claims, secret) | expect_ok?)
		outcome := verify_token(token, secret, JwtCheck(at: 100, audience: "wanted"))
		expect_equal(outcome.err().kind, "EBADMSG")?

	nbf := (
		sign_token(
			(parse("\{\"nbf\":\"tomorrow\"\}") | expect_ok?),
			secret,
		) | expect_ok?
	)
	(failure(verify_token(nbf, secret, JwtCheck(at: 100)))?) | expect_equal(wrong)?

	fine := (
		sign_token(
			(parse("\{\"aud\":[\"wanted\"],\"exp\":200\}") | expect_ok?),
			secret,
		) | expect_ok?
	)
	_ := (
		verify_token(
			fine,
			secret,
			JwtCheck(at: 100, audience: "wanted"),
		) | expect_ok?
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
		(
			(failure(verify_token(token, secret, JwtCheck(at: 100)))?)
			| expect_equal(
				Error("jwt: claims must be an object", kind: "EBADMSG")
			)?
		)

test "claim object validation applies before typed payload decoding":
	secret := "secret".to_bytes()
	null_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bnVsbA.7DWrkJHEM03NP-M-9zlpZJ3Ud49InV9BpM_GlfnVpfM"
	number_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.NDI.DpSBf8asYLjZ8f-FNmbOgcAqnUgtEhVlF7yfz6fkGEo"
	array_token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.W10.ny0W7Pkele2S9JjQz1pcPuE-7_Jrt2VBqPEO1UnPyQg"
	invalid := Error("jwt: claims must be an object", kind: "EBADMSG")
	(failure(verify_token[Int?](null_token, secret))?) | expect_equal(invalid)?
	(failure(verify_token[Int](number_token, secret))?) | expect_equal(invalid)?
	(failure(verify_token[List[Int]](array_token, secret))?) | expect_equal(invalid)?

test "claim object validation follows signature verification":
	token := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.bnVsbA.7DWrkJHEM03NP-M-9zlpZJ3Ud49InV9BpM_GlfnVpfM"
	(
		(failure(verify_token(token, "other".to_bytes()))?)
		| expect_equal(Error("jwt: bad signature", kind: "EBADMSG"))?
	)

test "verify accepts empty claim objects and nested values":
	secret := "secret".to_bytes()
	empty := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-IDcSemACt8x4iTMCda8Yhe3iZaWbvV5XKSTbuAn0M"
	nested := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJuZXN0ZWQiOltdLCJhY3RpdmUiOnRydWV9.mgN1ikVmpILfLmGzXL3xy4bWgwTvpDt52bslkrtkIjM"
	claims := (verify_token(empty, secret) | expect_ok?)
	expect_true(claims.as_map().is_some())?
	claims.as_map().get().length() | expect_equal(0)?

	rich := (verify_token(nested, secret) | expect_ok?)
	rich.get("active").get().as_bool().get() | expect_equal(true)?
	rich.get("nested").get().as_list().get().length() | expect_equal(0)?

test "rs256 signs with a private key and verifies with the public key":
	private := (rsa_generate(2048) | expect_ok?)
	public := (public_key_der(private) | expect_ok?)
	token := (sign_token(session(1900000000), private, JwtAlgorithm.Rs256) | expect_ok?)
	check := JwtCheck(algorithm: JwtAlgorithm.Rs256)
	(verify_token[Session](token, public, check) | expect_ok?).sub | expect_equal("42")?

	other := (public_key_der((rsa_generate(2048) | expect_ok?)) | expect_ok?)
	(
		(failure(verify_token[Session](token, other, check))?) | expect_equal(
			Error("jwt: bad signature", kind: "EBADMSG")
		)?
	)

test "es256 signatures are raw 64 bytes and verify":
	private := (ecdsa_generate(Curve.P256) | expect_ok?)
	public := (public_key_der(private) | expect_ok?)
	check := JwtCheck(algorithm: JwtAlgorithm.Es256)

	for round in 0..20:
		token := (
			sign_token(
				session(1900000000 + round),
				private,
				JwtAlgorithm.Es256,
			) | expect_ok?
		)
		token.split(".")[2].length() | expect_equal(86)?
		(
			(verify_token[Session](token, public, check) | expect_ok?).exp
			| expect_equal(1900000000 + round)?
		)

	token := (sign_token(session(1), private, JwtAlgorithm.Es256) | expect_ok?)
	other := (public_key_der((ecdsa_generate(Curve.P256) | expect_ok?)) | expect_ok?)
	(
		(failure(verify_token[Session](token, other, check))?) | expect_equal(
			Error("jwt: bad signature", kind: "EBADMSG")
		)?
	)

test "eddsa signs with a seed and verifies with the public key":
	seed := (random_bytes(32) | expect_ok?)
	public := (public_key(seed) | expect_ok?)
	check := JwtCheck(algorithm: JwtAlgorithm.EdDsa)
	token := (sign_token(session(1900000000), seed, JwtAlgorithm.EdDsa) | expect_ok?)
	(verify_token[Session](token, public, check) | expect_ok?).sub | expect_equal("42")?
	(
		(failure(verify_token[Session](token, public, JwtCheck()))?)
		| expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))?
	)

test "sign returns InvalidKey for a key that does not fit":
	result := sign_token(session(1), "short".to_bytes(), JwtAlgorithm.EdDsa)
	if _ := result: return fail("accepted")

	result | expect_equal(error(Error("jwt: invalid key", kind: "EINVAL")))?

// Independent HS256 signatures use key "secret" and payload {}. The comments
// show the exact protected headers, including malformed extension requirements.
test "verify rejects unsupported and malformed critical headers":
	secret := "secret".to_bytes()
	tokens := [
		// {"alg":"HS256","crit":["example"],"example":true}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOlsiZXhhbXBsZSJdLCJleGFtcGxlIjp0cnVlfQ.e30.a2vMv_4PubTvFXgyFiBLVpBZSgLLXqx2FsNpqa0WU7k",
		// {"alg":"HS256","crit":null}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOm51bGx9.e30.T7fEZQZRbMmzsEEF2hgSkpYLBezyECPXxdhBRmgVpC8",
		// {"alg":"HS256","crit":[]}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOltdfQ.e30.e5krqJ98ji87GRRAxDeXsEjeZ_NJrkB753cq1-K-7fM",
		// {"alg":"HS256","crit":"example"}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOiJleGFtcGxlIn0.e30.teCRyuZjo1_D9iVNRh56ytipFddD-cls2HSSPUWaCe8",
		// {"alg":"HS256","crit":1}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOjF9.e30.emGIS6di3OdxAlvwHO-Jv83R8EQ2vgvd4IjI8D7nxXA",
		// {"alg":"HS256","crit":{}}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOnt9fQ.e30.kMiCqh170NlKnvBlUJCVzie3njXo8CcCU7z1ooz-Ve8",
		// {"alg":"HS256","crit":["example",1]}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOlsiZXhhbXBsZSIsMV19.e30.j23zJyHsurzzamgJMM4lrZmlGNBnwLK2kTmtmQHwEkA",
		// {"alg":"HS256","crit":["missing"]}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOlsibWlzc2luZyJdfQ.e30.HtORK809lPKiPRwJYpnyFEhfW--xdouBptB1qB-kBMg",
		// {"alg":"HS256","crit":["example","example"],"example":true}
		"eyJhbGciOiJIUzI1NiIsImNyaXQiOlsiZXhhbXBsZSIsImV4YW1wbGUiXSwiZXhhbXBsZSI6dHJ1ZX0.e30.VFsrdRy355Mrq6dUXgCAbRyMAKrND-EKIHINEDy25ks",
		// {"alg":"HS256","b64":false,"crit":["b64"]}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6ZmFsc2UsImNyaXQiOlsiYjY0Il19.e30.eQMUUVQWh2OWV9Bmuu4Hid5-hgcjvjrLVMSCB33vgqw",
		// {"alg":"HS256","b64":true,"crit":["b64"]}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6dHJ1ZSwiY3JpdCI6WyJiNjQiXX0.e30.kKndt9ePg2M-HhRwHLtmeT-Ll926VPZM5GW_Z_HVeWE",
	]
	for token in tokens:
		(
			(failure(verify_token(token, secret))?)
			| expect_equal(
				Error(
					"jwt: unsupported critical header",
					kind: "EBADMSG",
				)
			)?
		)

test "verify rejects unencoded and malformed payload encoding headers":
	secret := "secret".to_bytes()
	tokens := [
		// {"alg":"HS256","b64":false}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6ZmFsc2V9.e30.MrPklHP0bSjz-ji2syy7IlytGKYSnllWokCMIPI-hzs",
		// {"alg":"HS256","b64":null}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6bnVsbH0.e30.TdVTSqkWAoCUAezp3U37AZ0vLraK0QlPI1H8Gqv6ip4",
		// {"alg":"HS256","b64":"true"}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6InRydWUifQ.e30.d0hBESzMeJx_580gjgf3rYbA1yp7Y1V2YpgDMGHeNEI",
		// {"alg":"HS256","b64":1}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6MX0.e30.aDX92yXhxyYcczIejOqfvmj-35By3-pz8WAUPa3wDf0",
		// {"alg":"HS256","b64":[]}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6W119.e30.LkqPuote-_4HO3fD6qhi6L4lS7rPMYnRQnyo7HmOpTA",
		// {"alg":"HS256","b64":{}}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6e319.e30.CpuY69nnDgJh7Nown0j8JP69DHt7DVidzzU1MfpguRo",
	]
	for token in tokens:
		(
			(failure(verify_token(token, secret))?)
			| expect_equal(
				Error(
					"jwt: unsupported payload encoding",
					kind: "EBADMSG",
				)
			)?
		)

test "verify keeps unknown noncritical and default encoding headers":
	secret := "secret".to_bytes()
	tokens := [
		// {"alg":"HS256"}
		"eyJhbGciOiJIUzI1NiJ9.e30.XmNK3GpH3Ys_7wsYBfq4C3M6goz71I7dTgUkuIa5lyQ",
		// {"alg":"HS256","example":true}
		"eyJhbGciOiJIUzI1NiIsImV4YW1wbGUiOnRydWV9.e30.gGkj567vlhKu9tUUmUaaXKBgZiS_h_2m3I-WjSOAKC0",
		// {"alg":"HS256","b64":true}
		"eyJhbGciOiJIUzI1NiIsImI2NCI6dHJ1ZX0.e30.ytT3DcpwW1EYxFw4uI1jWb4NvSt0e3e2HCRZar54MpM",
		// {"alg":"HS256","example":{"crit":["unknown"]}}
		"eyJhbGciOiJIUzI1NiIsImV4YW1wbGUiOnsiY3JpdCI6WyJ1bmtub3duIl19fQ.e30._lEWMGZGyrcSAeFILDUL31ZCjeVp6DnNU9nssDc6Yu8",
	]

	for token in tokens:
		claims := (verify_token(token, secret) | expect_ok?)
		expect_true(claims.as_map().is_some())?
		claims.as_map().get().length() | expect_equal(0)?
		(
			(failure(verify_token(token, "other".to_bytes()))?)
			| expect_equal(Error("jwt: bad signature", kind: "EBADMSG"))?
		)

test "configured algorithm validation precedes unsupported headers":
	token := "eyJhbGciOiJIUzI1NiIsImNyaXQiOlsiZXhhbXBsZSJdLCJleGFtcGxlIjp0cnVlfQ.e30.a2vMv_4PubTvFXgyFiBLVpBZSgLLXqx2FsNpqa0WU7k"
	(
		(
			failure(
				verify_token(
					token,
					"secret".to_bytes(),
					JwtCheck(algorithm: JwtAlgorithm.Hs512),
				)
			)?
		)
		| expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))?
	)

test "verify rejects missing and nonstring algorithm names":
	tokens := [
		// {}
		"e30.e30.FCSDuqmCuL_yoq1hx-E3IJO5tSEpcgFbqwcZf590zhA",
		// {"alg":null}
		"eyJhbGciOm51bGx9.e30.D-sClfNt-cvX7ieuCLdiRbaME_Fv8F1NKCEEVhk_5As",
		// {"alg":1}
		"eyJhbGciOjF9.e30.Ow07NLUThAwtbjL_TGzVy6NvlTMwTHJPgkYZm62Sndw",
		// {"alg":[]}
		"eyJhbGciOltdfQ.e30.OWVwnk-PMcDN05dcs-txC3JgGFTC4Zv2-MyROCHH430",
		// {"alg":{}}
		"eyJhbGciOnt9fQ.e30.QzYcMTAAAXYy9GQSBLYh6yrTOZoRtFO8jr27wCwEhTY",
		// {"alg":true}
		"eyJhbGciOnRydWV9.e30.5nSaIwFMnTbuwwl-QAZ4zVqTV_qUadKxG_UpKNNIe6Y",
		// {"alg":""}
		"eyJhbGciOiIifQ.e30.eHpAX4gmdcAz1N_XANGlZqo-RN4PiuCyyS6tIel6RDI",
	]
	for token in tokens:
		(
			(failure(verify_token(token, "secret".to_bytes()))?)
			| expect_equal(Error("jwt: wrong algorithm", kind: "EBADMSG"))?
		)

// Sign NumberValue directly so JSON retains every decimal/exponent digit.
fn dated_token(name: String, number: String) String!:
	var claims = Map[String, JsonValue]()
	claims.add(name.clone(), JsonValue.NumberValue(number.clone()))
	return sign_token(JsonValue.ObjectValue(claims), "secret".to_bytes())

fn expect_date_order(number: String, at: Int, order: Int) Unit!:
	secret := "secret".to_bytes()
	exp := dated_token("exp", number)?
	nbf := dated_token("nbf", number)?
	check := JwtCheck(at: at)

	if order <= 0:
		(
			(failure(verify_token(exp, secret, check))?)
			| expect_equal(Error("jwt: token expired", kind: "EBADMSG"))?
		)

		_ := verify_token(nbf, secret, check)?
	else:
		_ := verify_token(exp, secret, check)?
		(
			(failure(verify_token(nbf, secret, check))?)
			| expect_equal(
				Error("jwt: token not yet valid", kind: "EBADMSG")
			)?
		)

	return ok(unit)

test "numeric dates retain consecutive integer and fractional ordering":
	expect_date_order("9007199254740993", 9007199254740992, 1)?
	expect_date_order("9007199254740992", 9007199254740993, -1)?
	expect_date_order("-9007199254740993", -9007199254740992, -1)?
	expect_date_order("-9007199254740992", -9007199254740993, 1)?
	expect_date_order("1700000000.0000001", 1700000000, 1)?
	expect_date_order("1699999999.9999999", 1700000000, -1)?
	expect_date_order("-1700000000.0000001", -1700000000, -1)?
	expect_date_order("-1699999999.9999999", -1700000000, 1)?
	expect_date_order("9223372036854775807", 9223372036854775807, 0)?
	expect_date_order("9223372036854775808", 9223372036854775807, 1)?
	expect_date_order("-9223372036854775808", -9223372036854775808, 0)?
	expect_date_order("-9223372036854775809", -9223372036854775808, -1)?

test "numeric date exponents and signed zero preserve exact boundaries":
	for zero in ["0", "-0", "0.000", "-0.000e99999999999999999999"]:
		expect_date_order(zero, 0, 0)?
		expect_date_order(zero, -1, 1)?
		expect_date_order(zero, 1, -1)?

	for one in ["1", "1.00", "10e-1", "0.01E+0002", "1000e-3", "1e-000", "1E+000"]:
		expect_date_order(one, 1, 0)?
	for minus_one in ["-1", "-1.00", "-10e-1", "-0.01E+0002", "-1e-000", "-1E+000"]:
		expect_date_order(minus_one, -1, 0)?
	expect_date_order("1e-999999999999999999999", 0, 1)?
	expect_date_order("1e-999999999999999999999", 1, -1)?
	expect_date_order("-1e-999999999999999999999", 0, -1)?
	expect_date_order("-1e-999999999999999999999", -1, 1)?
	expect_date_order("1e999999999999999999999", 9223372036854775807, 1)?
	expect_date_order("-1e999999999999999999999", -9223372036854775808, -1)?
	expect_date_order("1e+" + "0".repeat(1000).get("") + "1", 10, 0)?
	expect_date_order("1e" + "9".repeat(8000).get(""), 1, 1)?
	expect_date_order("1e-" + "9".repeat(8000).get(""), 1, -1)?

	// The exponent must cancel a long coefficient's scale before comparison.
	expect_date_order("1" + "0".repeat(1000).get("") + "e-1000", 1, 0)?
	expect_date_order("0." + "0".repeat(1000).get("") + "1e1001", 1, 0)?
	expect_date_order("1." + "0".repeat(1000).get("") + "1", 1, 1)?

test "numeric date leeway is exact across Int boundaries":
	secret := "secret".to_bytes()

	for number in ["9007199254740993", "9007199254740992.0000001"]:
		exp := dated_token("exp", number)?
		_ := verify_token(exp, secret, JwtCheck(at: 9007199254740993, leeway: 1))?
		nbf := dated_token("nbf", number)?
		_ := verify_token(nbf, secret, JwtCheck(at: 9007199254740992, leeway: 1))?

	exp_limit := dated_token("exp", "18446744073709551615")?
	(
		(
			failure(
				verify_token(
					exp_limit,
					secret,
					JwtCheck(
						at: 9223372036854775807,
						leeway: -9223372036854775808,
					),
				)
			)?
		)
		| expect_equal(Error("jwt: token expired", kind: "EBADMSG"))?
	)

	exp_later := dated_token("exp", "18446744073709551615.0000001")?
	_ := verify_token(
		exp_later,
		secret,
		JwtCheck(at: 9223372036854775807, leeway: -9223372036854775808),
	)?
	nbf_limit := dated_token("nbf", "-18446744073709551616")?
	_ := verify_token(
		nbf_limit,
		secret,
		JwtCheck(at: -9223372036854775808, leeway: -9223372036854775808),
	)?
	nbf_later := dated_token("nbf", "-18446744073709551615.9999999")?
	(
		(
			failure(
				verify_token(
					nbf_later,
					secret,
					JwtCheck(
						at: -9223372036854775808,
						leeway: -9223372036854775808,
					),
				)
			)?
		)
		| expect_equal(Error("jwt: token not yet valid", kind: "EBADMSG"))?
	)

	// Positive leeway can also put the boundary outside Int.
	exp_early := dated_token("exp", "-18446744073709551615")?
	(
		(
			failure(
				verify_token(
					exp_early,
					secret,
					JwtCheck(
						at: -9223372036854775808,
						leeway: 9223372036854775807,
					),
				)
			)?
		)
		| expect_equal(Error("jwt: token expired", kind: "EBADMSG"))?
	)

	nbf_late := dated_token("nbf", "18446744073709551614")?
	_ := verify_token(
		nbf_late,
		secret,
		JwtCheck(at: 9223372036854775807, leeway: 9223372036854775807),
	)?

test "numeric date validation still follows signature verification":
	token := dated_token("nbf", "1e999999999999999999999")?
	(
		(failure(verify_token(token, "other".to_bytes(), JwtCheck(at: 0)))?)
		| expect_equal(Error("jwt: bad signature", kind: "EBADMSG"))?
	)
