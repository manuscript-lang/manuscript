import {expect_equal} from "@std/testing.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) -> String:
    let {id: {value}, name: display_name} = customer
    return "{value}: {display_name}"

test "nominal record and nested binding":
    let customer = Customer(id: CustomerId("c1"), name: "Ada")
    customer_name(customer: customer) | try expect_equal(expected: "c1: Ada")
