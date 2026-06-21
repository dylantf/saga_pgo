---
title: SagaPgo.Types
---

## Types

### Value

```saga
opaque type Value
```

### Uuid

```saga
opaque type Uuid
```

A Postgres UUID. Internally a 36-character canonical hyphenated string.

## Functions

### pg_null

```saga
fun pg_null : Unit -> Value
```

### pg_int

```saga
fun pg_int : Int -> Value
```

### pg_float

```saga
fun pg_float : Float -> Value
```

### pg_text

```saga
fun pg_text : String -> Value
```

### pg_bool

```saga
fun pg_bool : Bool -> Value
```

### pg_uuid

```saga
fun pg_uuid : Uuid -> Value
```

Encode a Uuid as a query parameter.

### pg_date

```saga
fun pg_date : Date -> Value
```

Encode a Date as a query parameter for Postgres DATE columns.

### pg_naive_datetime

```saga
fun pg_naive_datetime : NaiveDateTime -> Value
```

Encode a NaiveDateTime as a query parameter for Postgres TIMESTAMP and
TIMESTAMPTZ columns. The value is treated as being in UTC.

### pg_time

```saga
fun pg_time : Time -> Value
```

Encode a Time as a query parameter for Postgres TIME columns.

### maybe_null

```saga
fun maybe_null : a -> Value -> Maybe a -> Value
```

Encode an optional value as a query parameter, emitting NULL when the
value is `Nothing`. Takes an encoder function so it composes with any
value encoder:

maybe_null text maybe_username
maybe_null int_value maybe_age
maybe_null date_value maybe_birthday

### naive_datetime

```saga
fun naive_datetime : Decoder NaiveDateTime
```

Decoder for Postgres TIMESTAMP and TIMESTAMPTZ columns.
Both are decoded to a NaiveDateTime in UTC.

### date

```saga
fun date : Decoder Date
```

Decoder for Postgres DATE columns.

### time

```saga
fun time : Decoder Time
```

Decoder for Postgres TIME columns.

### parse_uuid

```saga
fun parse_uuid : String -> Result Uuid String
```

Parse a string into a Uuid. Accepts canonical hyphenated form.

### uuid

```saga
fun uuid : Decoder Uuid
```

Decoder for Postgres UUID columns.

