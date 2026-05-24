# Getting started

A short walk through wiring up a connection and running your first
query.

## Install

Add `saga_pgo` to your `project.toml`:

```toml
[deps]
saga_pgo = { git = "https://github.com/dylantf/saga_pgo" }
```

Then `saga install` to fetch it.

## Configure a connection

A `Config` describes how to reach the database. `default_config` fills
in sensible defaults (localhost, port 5432, postgres user, no
password) and you override what you need with a record update:

```saga
import SagaPgo (default_config, connect)

let config =
  { default_config "mydb" |
    user: "postgres",
    password: "postgres",
    port: 5432,
  }

let conn = connect config
```

`connect` starts a `pgo` pool and gives you back a `Connection`
handle. The handle is what you pass to every query, execute, and
transaction call. Multiple `connect` calls give you multiple
independent pools — handy for a read replica plus primary, or
sharding.

## Handlers

The `Postgres` effect describes *how* SQL gets executed. The library
ships a real handler — `pg` — that talks to `pgo`. Install it at the
top of your effectful block with `with`:

```saga
import SagaPgo (pg, query)
import SagaPgo.Types as T

main () = {
  let conn = connect config
  let _ = query conn "INSERT INTO users (name) VALUES ($1)" [T.pg_text "Alice"]
  println "inserted"
} with {pg, console}
```

For transactions, also install `pg_transaction` — see the
[transactions guide](transactions.md).

## Two ways to run a query

The low-level primitive is `query`. It takes a SQL string and a flat
list of `Value` parameters:

```saga
query conn "SELECT id FROM users WHERE name = $1" [T.pg_text "Alice"]
```

For anything more than a one-liner, prefer the builder. It tracks
placeholder numbering for you and composes cleanly:

```saga
sql "SELECT id, name FROM users"
|> push "WHERE name ="
|> push_bind (T.pg_text "Alice")
|> execute conn
```

Both return `Result (Returned Dynamic) QueryError`. `Returned` carries
the row count and a list of rows; each row is `Dynamic`, so you
decode columns out of it positionally — see the [types and decoding
guide](types-and-decoding.md).

## What's next

- [Queries](queries.md) — the builder in depth, including bulk inserts
  with `push_values`.
- [Transactions](transactions.md) — wrapping work in a transaction and
  the rules around it.
- [Types and decoding](types-and-decoding.md) — encoding parameters
  and decoding columns back into Saga values.
