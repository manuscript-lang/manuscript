import {expect_equal} from "@std/testing.ms"

type CustomerId:
    value: String

type OrderId:
    value: String

type Customer:
    id: CustomerId
    name: String

fn customer_name(customer: Customer) String:
    let {id: {value}, name: display_name} = customer

    return "{value}: {display_name}"

test "nominal record and nested binding":
    let customer = Customer(CustomerId("c1"), "Ada")

    try expect_equal(customer_name(customer), "c1: Ada")
