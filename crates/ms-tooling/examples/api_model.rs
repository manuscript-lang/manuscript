//! Temporary oracle for the Manuscript docs port: prints the whole API model (every `ApiModule` field,
//! including the source excerpts the public JSON omits) as JSON. Deleted with the Rust docs generator.
use ms_tooling::guide::json::Json;
use ms_tooling::guide::standard_library;

fn strings(items: &[String]) -> Json {
    Json::strings(items)
}

fn main() {
    let syms = ms_syntax::Names::global();
    let modules: Vec<Json> = standard_library(syms)
        .iter()
        .map(|m| {
            let declarations = m
                .declarations
                .iter()
                .map(|d| {
                    let members = d
                        .members
                        .iter()
                        .map(|x| {
                            Json::Obj(vec![
                                ("name".into(), Json::str(&x.name)),
                                ("kind".into(), Json::str(&x.kind)),
                                ("signature".into(), Json::str(&x.signature)),
                                ("doc".into(), Json::str(&x.doc)),
                                ("contract".into(), Json::str(&x.contract)),
                                ("legacy_contract".into(), Json::str(&x.legacy_contract)),
                            ])
                        })
                        .collect();
                    Json::Obj(vec![
                        ("declaration".into(), Json::str(&d.declaration)),
                        ("name".into(), Json::str(&d.name)),
                        ("doc".into(), Json::str(&d.doc)),
                        ("effects".into(), strings(&d.effects)),
                        ("kind".into(), Json::str(&d.kind)),
                        ("opaque".into(), Json::Bool(d.opaque)),
                        ("type".into(), Json::str(&d.ty)),
                        ("type_parameters".into(), strings(&d.parameters)),
                        ("fields".into(), strings(&d.fields)),
                        ("cases".into(), strings(&d.cases)),
                        ("operations".into(), strings(&d.operations)),
                        ("members".into(), Json::Arr(members)),
                        ("implements".into(), strings(&d.implements)),
                        (
                            "implementation_declarations".into(),
                            strings(&d.implementation_declarations),
                        ),
                    ])
                })
                .collect();
            Json::Obj(vec![
                ("path".into(), Json::str(&m.path)),
                ("declarations".into(), Json::Arr(declarations)),
            ])
        })
        .collect();
    let value = Json::Obj(vec![("modules".into(), Json::Arr(modules))]);
    println!("{}", value.pretty_line(ms_json::Escape::HtmlSafe));
}
