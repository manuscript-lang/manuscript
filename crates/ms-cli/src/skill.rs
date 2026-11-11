//! Install the compiler's self-contained agent skill in a chosen directory.

use std::io::Write;
use std::path::Path;

use crate::backend::Io;

pub fn run_skill(args: &[String], io: &mut Io) -> i32 {
    let mut output = ".agents/skills";
    let mut seen_output = false;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        if !matches!(arg.as_str(), "-o" | "--output") || seen_output {
            return crate::util::usage_error(
                io,
                "ms skill takes only -o <directory>; run ms skill --help",
            );
        }
        let Some(directory) = args.next() else {
            return crate::util::usage_error(io, "ms skill -o needs a parent directory");
        };
        if directory.is_empty() || directory.starts_with('-') {
            return crate::util::usage_error(
                io,
                "ms skill -o needs a nonempty parent directory; prefix a leading dash with ./",
            );
        }
        output = directory;
        seen_output = true;
    }
    let destination = Path::new(output).join("manuscript");
    if let Err(error) = install(Path::new(output), &destination) {
        let _ = writeln!(
            io.stderr,
            "ms skill: cannot write {}: {error}; existing skill files are never overwritten; choose another output directory or review and remove the existing folder before retrying",
            destination.display()
        );
        return 1;
    }
    let _ = writeln!(
        io.stdout,
        "Wrote Manuscript {} agent skill to {}",
        crate::VERSION,
        destination.display()
    );
    0
}

fn install(parent: &Path, destination: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(parent)?;
    // Reserve the whole skill folder first. Refuse existing files/directories,
    // including an earlier generated skill, rather than replace local edits.
    std::fs::create_dir(destination)?;
    std::fs::create_dir(destination.join("references"))?;
    for (name, text) in ms_tooling::guide::skill::FILES {
        let text = text.replace("{{MS_VERSION}}", crate::VERSION);
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(destination.join(name))?;
        file.write_all(text.as_bytes())?;
    }
    Ok(())
}
