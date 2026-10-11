# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"

export interface System:
    fn environment(name: String) -> Optional[String]
    fn info() -> SystemInfo
    fn working_directory() -> String

export type SystemInfo:
    os: String
    architecture: String
    cpu_count: Int
