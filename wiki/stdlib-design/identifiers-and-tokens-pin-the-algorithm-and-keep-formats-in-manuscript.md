[Wiki](../index.md) › [Standard-library design](index.md)

# Identifiers, config text and tokens are written in Manuscript, and a verifier pins its algorithm

Verified: `data/uuid.ms` (v5, v7), `random.ms` (`ulid`, `token`), `data/config.ms` (`parse_dotenv`, `parse_ini`) and `data/jwt.ms` are plain `.ms` over `crypto`, `encoding`, `json` and `time`, with no Rust. `process.control().load_environment` still uses the Rust `.env` parser; `parse_dotenv` accepts the same syntax and only returns a map, so layering is `values.add` over real variables.
Decision (P1 scope): `verify_token` takes the one accepted algorithm in `JwtCheck`, never the token header's claim, so `none` and algorithm swaps are `WrongAlgorithm`; the signature is checked before claims are decoded. ES256 converts between the crypto module's DER signatures and JWS `r||s` in `.ms`.
Gotchas: a stdlib module is embedded at build, so `cargo build -p ms-cli` is needed before `ms test` sees an edit; one syntax error in any `stdlib/**.ms` panics every command. Time- and entropy-dependent ids have no conformance fixtures (the harvester skips `time`/`random`); their fixtures live in `tests/conformance/fixtures/e2e/stdlib`.

Apply when: adding an id, token, signed-value or config-format helper.
Evidence: `tests/conformance/fixtures/e2e/stdlib/{uuid,config,jwt}.ms`.
Verify: `ms test` on those fixtures after `cargo build --release --locked -p ms-cli`.

INI inline comments depend on the original assignment suffix: trim only a separate view for matching quotes, then find ` #` / ` ;` before trimming the bare result. Trimming first turns an empty value's comment into data (#3092). `config.ms` fixtures also pin unspaced markers and tabs as literal, avoiding an accidental syntax expansion.
