type DomainError:
    case Invalid

type OtherError:
    case Rejected

fn domain_failure() Int!DomainError:
    return error(DomainError.Invalid)

fn common_boundary() Int!:
    return domain_failure()

fn propagated_boundary() Int!:
    let value = try domain_failure()
    return ok(value)

fn unrelated_boundary() Int!OtherError:
    let value = try domain_failure()
    return ok(value)

fn optional_result(value: Int!String?) Int:
    return value.get().get(-1)

fn unrelated_optional_error() Int:
    return optional_result(error(7))
