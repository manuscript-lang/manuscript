[Wiki](../index.md) › [Standard-library design](index.md)

# Identifiers, config text and tokens are written in Manuscript, and a verifier pins its algorithm

Verified: `data/uuid.ms` (v5, v7), `random.ms` (`ulid`, `token`), `data/config.ms` (`parse_dotenv`, `parse_ini`) and `data/jwt.ms` are plain `.ms` over `crypto`, `encoding`, `json` and `time`, with no Rust. `env.load_environment` is `.ms` too (read file, `parse_dotenv`, `set_environment` for names not already set); the Rust `.env` parser was deleted after a 400-file differential run matched. Known difference: an existing variable whose value is not UTF-8 is invisible to `environment()`, so a file entry of the same name replaces it.
Decision (P1 scope): `verify_token` takes the one accepted algorithm in `JwtCheck`, never the token header's claim, so `none` and algorithm swaps are `WrongAlgorithm`; the signature is checked before claims are decoded. ES256 converts between the crypto module's DER signatures and JWS `r||s` in `.ms`.
Gotchas: a stdlib module is embedded at build, so `cmake --build --preset ci` is needed before `ms test` sees an edit; one syntax error in any `src/stdlib/**.ms` stops every command. Time- and entropy-dependent ids have no conformance fixtures (the harvester skips `time`/`random`); their fixtures live in `tests/conformance/fixtures/e2e/stdlib`.

Apply when: adding an id, token, signed-value or config-format helper.
Evidence: `tests/conformance/fixtures/e2e/stdlib/{uuid,config,jwt}.ms`.
Verify: `ms test` on those fixtures after `cmake --build --preset ci`.

INI inline comments depend on the original assignment suffix: trim only a separate view for matching quotes, then find ` #` / ` ;` before trimming the bare result. Trimming first turns an empty value's comment into data (#3092). `config.ms` fixtures also pin unspaced markers and tabs as literal, avoiding an accidental syntax expansion.
