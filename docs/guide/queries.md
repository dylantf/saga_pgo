# Queries

How to run SQL against a `Connection`. Two layers: the `query`
primitive for one-shot statements, and the `sql` builder for anything
you want to compose.

## `query`: the primitive

`query` takes a connection, a SQL string with `$N` placeholders, and a
flat list of `Value` parameters:

```saga
query conn
  "INSERT INTO users (name, age) VALUES ($1, $2)"
  [T.pg_text "Alice", T.pg_int 30]
```

It returns `Result (Returned Dynamic) QueryError`. Use it when the
statement is fully formed and you don't need to splice fragments
together.

## `sql` and `execute`: the builder

The builder accumulates SQL fragments and parameters and finalizes
with `execute`:

```saga
sql "SELECT id, name FROM users WHERE name ="
|> push_bind (T.pg_text "Alice")
|> execute conn
```

The builder owns placeholder numbering. As you call `push_bind` and
`push_values` it emits `$1`, `$2`, ... in order — you never write
`$N` yourself.

### `push`

Append a raw SQL fragment. A leading space is added for you so you
don't have to fight whitespace:

```saga
sql "SELECT *"
|> push "FROM users"
|> push "WHERE active = true"
```

### `push_bind`

Bind one parameter and emit ` $N` at the current position. Reads
cleanly after an operator:

```saga
sql "SELECT id FROM users WHERE name ="
|> push_bind (T.pg_text "Alice")
|> push "AND age >"
|> push_bind (T.pg_int 18)
```

### `bind_values`

If your SQL fragment already contains `$1, $2, ...` placeholders,
attach the values without emitting any new SQL:

```saga
sql "INSERT INTO users (name, age) VALUES ($1, $2)"
|> bind_values [T.pg_text "Alice", T.pg_int 30]
|> execute conn
```

Don't mix `bind_values` with `push_bind` / `push_values` in the same
query — pick one numbering strategy and stick with it.

### `push_values`: bulk inserts

`push_values` emits `(p1, p2, ...), (p3, p4, ...), ...` row groups,
flattening parameters and auto-numbering placeholders. The first call
emits ` values `; subsequent calls append more rows, separated by
commas:

```saga
let new_users = [
  NewUser { name: "Bob", age: 25 },
  NewUser { name: "Carol", age: 28 },
  NewUser { name: "Dave", age: 35 },
]

sql "INSERT INTO users (name, age)"
|> push_values new_users (fun u -> [T.pg_text u.name, T.pg_int u.age])
|> push "RETURNING id"
|> execute conn
```

An empty list of rows is a no-op. Don't push non-values fragments
between two consecutive `push_values` calls or the joining comma will
produce broken SQL — finish all your value rows first, then `push`
the trailing clause.

## The result

A successful query returns `Returned { count, rows }`. `count` is the
number of rows affected (or returned, for `SELECT`); `rows` is a list
of `Dynamic` values, one per row, that you decode positionally. See
the [types and decoding guide](types-and-decoding.md) for how to
extract typed columns.

## Errors

`QueryError` is an ADT. The most useful constructors:

- `ConstraintViolated message constraint detail` — unique / foreign
  key / check violations. `constraint` is the constraint name.
- `PostgresqlError code severity message` — anything Postgres returned
  that wasn't a constraint violation. `code` is the SQLSTATE.
- `UnexpectedArgumentCount expected got` — you bound the wrong number
  of parameters for the placeholders in the SQL.
- `UnexpectedArgumentType expected got` — a parameter's type didn't
  match what the column expected.
- `QueryTimeout`, `ConnectionUnavailable` — pool-level failures.

`QueryError` derives `Debug`, so `println $"{err}"` is enough during
development.
