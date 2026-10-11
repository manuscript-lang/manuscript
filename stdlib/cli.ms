# Canonical standard-library declarations. Implementations are native.

import Clock from "@std/time.ms"
import Commands from "@std/process.ms"
import Entropy from "@std/random.ms"
import FileSystem from "@std/fs.ms"
import Files from "@std/io.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Network from "@std/http.ms"
import ReadStream from "@std/io.ms"
import System from "@std/system.ms"
import WallClock from "@std/time.ms"
import WriteStream from "@std/io.ms"

export type Process:
    arguments: List[String]
    environment: Map[String, String]
    stdin: ReadStream & Shareable
    stdout: WriteStream & Shareable
    stderr: WriteStream & Shareable
    files: Files & Shareable
    clock: Clock & Shareable
    network: Network & Shareable
    commands: Commands & Shareable
    filesystem: FileSystem & Shareable
    entropy: Entropy & Shareable
    wall_clock: WallClock & Shareable
    system: System & Shareable
