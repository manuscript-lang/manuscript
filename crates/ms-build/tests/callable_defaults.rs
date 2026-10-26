//! Erasing omission permissions must still adapt a supplied argument's representation.

use ms_driver::{CheckRequest, check_graph, load_file};
use ms_lower::{Options, lower_program};
use ms_rt as _;
use std::path::PathBuf;

fn lower(name: &str, source: &str) {
    let root = std::env::temp_dir().join(format!(
        "ms-callable-defaults-{}-{name}",
        std::process::id()
    ));
    std::fs::create_dir_all(&root).expect("directory");
    let file: PathBuf = root.join("main.ms");
    std::fs::write(&file, source).expect("source");
    let checked = check_graph(
        load_file(&file.to_string_lossy(), Default::default()),
        CheckRequest::default(),
    );
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let module = lower_program(
        &checked.program.expect("program"),
        &Options {
            entry: checked.entry,
        },
    )
    .expect("accepted source lowers");
    ms_mir::verify::verify_module(&module).expect("verified MIR");
    std::fs::remove_dir_all(&root).expect("cleanup");
}

#[test]
fn required_source_function_can_replace_a_defaulted_callable() {
    lower(
        "source",
        "def original(value: Int = 7) -> Int: value + 1\ndef replacement(value: Int) -> Int: value + 2\nexport def main() -> Int:\n    var callback = original\n    callback = replacement\n    return callback(3)\n",
    );
}

#[test]
fn required_lambda_can_replace_a_defaulted_callable() {
    lower(
        "lambda",
        "def original(value: Int = 7) -> Int: value + 1\nexport def main() -> Int:\n    var callback = original\n    callback = lambda (value: Int): value + 2\n    return callback(3)\n",
    );
}

#[test]
fn required_native_function_can_replace_a_defaulted_callable() {
    lower(
        "native",
        "from \"@std/math.ms\" import floor\ndef original(value: Float = 7.0) -> Float: value\nexport def main() -> Int:\n    var callback = original\n    callback = floor\n    let _result = callback(3.5)\n    return 0\n",
    );
}

#[test]
fn required_bound_method_can_replace_a_defaulted_callable() {
    lower(
        "method",
        "type Offset:\n    base: Int\nimpl Offset:\n    def original(value: Int = 7) -> Int: self.base + value\n    def replacement(value: Int) -> Int: self.base + value + 1\nexport def main() -> Int:\n    let offset = Offset(2)\n    var callback = offset.original\n    callback = offset.replacement\n    return callback(3)\n",
    );
}

#[test]
fn generic_inference_adapts_defaulted_and_required_callables() {
    lower(
        "generic",
        "def original(value: Int = 7) -> Int: value + 1\ndef replacement(value: Int) -> Int: value + 2\ndef choose[T](left: T, right: T) -> T: right\nexport def main() -> Int:\n    return choose(original, replacement)(3)\n",
    );
}

#[test]
fn generic_calls_share_the_required_callable_representation() {
    lower(
        "instances",
        "def original(value: Int = 7) -> Int: value + 1\ndef replacement(value: Int) -> Int: value + 2\ndef choose[T](left: T, right: T) -> T: right\nexport def main() -> Int:\n    let first = choose(original, replacement)(3)\n    let second = choose(replacement, original)(3)\n    return first + second\n",
    );
}

#[test]
fn erasing_defaults_does_not_permit_omitting_a_required_argument() {
    let bodies = [
        "    var callback = original\n    callback = replacement\n    return callback()\n",
        "    let callbacks = [original, replacement]\n    return callbacks[1]()\n",
        "    let callbacks = {\"known\": original, \"unknown\": replacement}\n    return callbacks[\"unknown\"]()\n",
        "    let factory = lambda (flag: Bool):\n        if flag:\n            return original\n        return replacement\n    return factory(False)()\n",
    ];
    for (index, body) in bodies.iter().enumerate() {
        let root = std::env::temp_dir().join(format!(
            "ms-callable-required-{}-{index}",
            std::process::id()
        ));
        std::fs::create_dir_all(&root).expect("directory");
        let file = root.join("main.ms");
        let source = format!(
            "def original(value: Int = 7) -> Int: value + 1\ndef replacement(value: Int) -> Int: value + 2\nexport def main() -> Int:\n{body}"
        );
        std::fs::write(&file, source).expect("source");
        let checked = check_graph(
            load_file(&file.to_string_lossy(), Default::default()),
            CheckRequest::default(),
        );
        let messages: Vec<_> = checked
            .diagnostics
            .iter()
            .map(|d| d.message.as_str())
            .collect();
        assert_eq!(messages.len(), 1, "{body}: {messages:?}");
        assert!(
            messages[0].starts_with("missing argument value"),
            "{body}: {messages:?}"
        );
        std::fs::remove_dir_all(root).expect("cleanup");
    }
}
