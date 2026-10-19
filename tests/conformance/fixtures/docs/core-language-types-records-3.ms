# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:29
# Rejected: required email is missing.
let incomplete = Customer(name: "Ada")
# Accepted: let fixes the binding, not the record fields.
customer.name = "Grace"
