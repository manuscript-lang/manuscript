[Wiki](../index.md) › [Standard-library design](index.md)

# Identifiers, config text and tokens are written in Manuscript, and a verifier pins its algorithm

Verified: `data/uuid.ms` (v5, v7), `os/random.ms` (`ulid`, `token`), `data/config.ms` (`parse_dotenv`, `parse_ini`) and `data/jwt.ms` are plain `.ms` over `crypto`, `encoding`, `json` and `time`, with no Rust. `process.control().load_environment` still uses the Rust `.env` parser; `parse_dotenv` accepts the same syntax and only returns a map, so layering is `values.add` over real variables.
Decision (P1 scope): `verify_token` takes the one accepted algorithm in `JwtCheck`, never the token header's claim, so `none` and algorithm swaps are `WrongAlgorithm`; the signature is checked before claims are decoded. ES256 converts between the crypto module's DER signatures and JWS `r||s` in `.ms`.
Gotchas: a stdlib module is embedded at build, so `cargo build -p ms-cli` is needed before `ms test` sees an edit; one syntax error in any `stdlib/**.ms` panics every command. Time- and entropy-dependent ids have no conformance fixtures (the harvester skips `time`/`random`); their fixtures live in `tests/e2e/testdata/stdlib`.

Apply when: adding an id, token, signed-value or config-format helper.
Evidence: `tests/e2e/testdata/stdlib/{uuid,config,jwt}.ms`.
Verify: `ms test` on those fixtures after `cargo build --release --locked -p ms-cli`.
