// Password authentication: md5 and SCRAM-SHA-256 (RFC 5802 / 7677), in pure Manuscript.
import (
	Bytes from "@std/bytes.ms",
	HashAlgorithm, constant_time_equal, xor_bytes from "@std/crypto/crypto.ms",
	base64_decode, base64_encode, hex_encode from "@std/data/encoding.ms",
	random_bytes from "@std/random.ms",
)

// The md5 password response: "md5" + md5(md5(password + user) hex + salt) hex.
export fn md5_password(user: String, password: String, salt: Bytes) String:
	inner := hex_encode(HashAlgorithm.Md5.digest("{password}{user}".to_bytes()))
	outer := HashAlgorithm.Md5.digest(inner.to_bytes().concat(salt))
	return "md5{hex_encode(outer)}"

fn failed(why: String) Error:
	return Error("postgres: SCRAM {why}", kind: "EACCES")

// State of one SCRAM-SHA-256 exchange, kept between the server's messages.
export type Scram:
	password: String
	nonce: String
	first_bare: String
	server_signature: Bytes

// Starts an exchange; `first` is the client-first message to send.
export fn scram_start(password: String) Scram!:
	nonce := base64_encode(random_bytes(18)?, padded: false)
	first := "n=,r={nonce}"
	return ok(Scram(password, nonce, first, Bytes([])))

fn Scram.first_message() Bytes:
	return "n,,{self.first_bare}".to_bytes()

fn attribute(parts: List[String], key: String) String?:
	for part in parts:
		if part.starts_with("{key}="): return part.slice(2, part.length()).get("")
	return none

// Answers the server-first message with the client-final message.
fn var Scram.respond(server_first: String) Bytes!:
	parts := server_first.split(",")
	combined := attribute(parts, "r").get("")
	salt_text := attribute(parts, "s").get("")
	count := attribute(parts, "i").get("0").parse_int().get(0)
	if not combined.starts_with(self.nonce) or salt_text.is_empty() or count < 1:
		return error(failed("server-first message is invalid"))

	salt := base64_decode(salt_text, max_bytes: 1024)?
	salted := HashAlgorithm.Sha256.derive_key(
		self.password.to_bytes(),
		salt,
		count,
		32,
	)?
	client_key := HashAlgorithm.Sha256.hmac(salted, "Client Key".to_bytes())?
	stored := HashAlgorithm.Sha256.digest(client_key)
	without_proof := "c=biws,r={combined}"
	auth_message := "{self.first_bare},{server_first},{without_proof}".to_bytes()
	signature := HashAlgorithm.Sha256.hmac(stored, auth_message)?
	proof := xor_bytes(client_key, signature)?
	server_key := HashAlgorithm.Sha256.hmac(salted, "Server Key".to_bytes())?
	self.server_signature = HashAlgorithm.Sha256.hmac(server_key, auth_message)?
	return ok("{without_proof},p={base64_encode(proof)}".to_bytes())

// Checks the server-final message proves the server knows the password.
fn Scram.verify(server_final: String) Unit!:
	if server_final.starts_with("e="): return error(failed("rejected: {server_final}"))

	sent := base64_decode(
		server_final.slice(2, server_final.length()).get(""),
		max_bytes: 64,
	)?
	if not constant_time_equal(sent, self.server_signature):
		return error(failed("server signature mismatch"))

	return ok(unit)
