import Process from "@std/cli.ms"
import List from "@std/collections.ms"

export fn main(process: Process) -> Int:
    match process.commands.run(program: "/bin/printf", arguments: ["hello"], input: "".to_bytes(), max_output_bytes: 64, timeout: 1.seconds):
        error(_):
            return 1
        ok(output):
            assert output.exit_code == 0
            process.stdout.write(data: output.stdout)
            return 0
