[Wiki](../index.md) › [Standard-library design](index.md)

# Options records as plain defaults; fetch helpers are methods

Decision: a function that takes a settings record declares it `options: FetchOptions = FetchOptions()`, never `FetchOptions? = none`, so callers write `fetch(url, FetchOptions(method: HttpMethod.Post))` without `some(...)`.

Apply when: adding a parameter that is a record of settings, choosing between an interface and a record for a type with one implementation, naming the operation that waits for work to end, adding a second spelling of a constructor, naming a combinator over a record (prefer a method with the List name), naming an error type (derive it from the type whose operations return it, unique across sibling modules), or adding a type that sends and receives (make it a `Transport` behind `Channel`).
Evidence: [fetch.ms](../../stdlib/fetch.ms), [fetch fixture](../../tests/e2e/testdata/stdlib/fetch.ms), [workers fixture](../../tests/conformance/fixtures/e2e/stdlib/workers.ms).
Verify: `ms test tests/e2e/testdata/stdlib/fetch.ms tests/conformance/fixtures/e2e/stdlib/workers.ms`; `ms search_symbol read_json` finds no declaration.
