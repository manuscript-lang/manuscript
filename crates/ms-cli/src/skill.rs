//! Print a self-contained agent skill, or install its files in a chosen directory.

use std::io::Write;
use std::path::Path;

use crate::backend::Io;

pub fn run_skill(args: &[String], io: &mut Io) -> i32 {
    let mut output = None;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        if !matches!(arg.as_str(), "-o" | "--output") || output.is_some() {
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
        output = Some(directory);
    }
    let Some(output) = output else {
        let text = ms_tooling::guide::skill::document(crate::VERSION);
        if let Err(error) = write!(io.stdout, "{text}")
            && error.kind() != std::io::ErrorKind::BrokenPipe
        {
            let _ = writeln!(
                io.stderr,
                "ms skill: cannot write stdout: {error}; check the output destination and re-run"
            );
            return 1;
        }
        return 0;
    };
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
