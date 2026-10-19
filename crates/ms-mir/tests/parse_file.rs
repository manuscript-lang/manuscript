//! Parses the file named by MS_MIR_FILE (debugging aid; skipped when unset).
#[test]
fn parse_env_file() {
    let Ok(p) = std::env::var("MS_MIR_FILE") else { return };
    let src = std::fs::read_to_string(&p).unwrap();
    match ms_mir::parse::parse_module(&src) {
        Ok(m) => {
            if let Err(e) = ms_mir::verify::verify_module(&m) {
                for x in e {
                    eprintln!("{x}");
                }
                panic!("verify failed");
            }
        }
        Err(e) => panic!("{e}"),
    }
}
