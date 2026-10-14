# Canonical standard-library declarations. Implementations are native.

# Returns the host-supplied startup arguments, excluding the executable path.
# Repeated calls share the same mutable list; mutations do not rewrite native argv.
export fn arguments() -> List[String]:

# Returns the startup environment snapshot, not the live process environment.
# Repeated calls share the same mutable map; mutations do not call set_environment.
export fn environment() -> Map[String, String]:
