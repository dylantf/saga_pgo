-module(saga_pgo_bridge).

-export([start_pool/1, query/4, coerce/1]).

coerce(Value) ->
    Value.

start_pool({sagapgo_Config, Host, Port, Database, User, Password, PoolSize, Ssl}) ->
    PoolName = binary_to_atom(Database, utf8),
    Options = #{
        host => binary_to_list(Host),
        port => Port,
        database => Database,
        user => User,
        password => Password,
        pool_size => PoolSize,
        ssl => Ssl =:= true
    },
    case pgo_pool:start_link(PoolName, Options) of
        {ok, _Pid} ->
            {sagapgo_Connection, PoolName};
        {error, Reason} ->
            erlang:error({pgo_start_failed, Reason})
    end.

query({sagapgo_Connection, Pool}, Sql, Params, _Decoder) ->
    Options = #{pool => Pool},
    case pgo:query(Sql, Params, Options) of
        #{rows := Rows, num_rows := NumRows} ->
            {ok, {sagapgo_Returned, NumRows, Rows}};
        {error, Error} ->
            {error, convert_error(Error)}
    end.

convert_error(none_available) ->
    {sagapgo_ConnectionUnavailable};
convert_error({pgo_protocol, {parameters, Expected, Got}}) ->
    {sagapgo_UnexpectedArgumentCount, Expected, Got};
convert_error({pgsql_error, #{
    message := Message,
    constraint := Constraint,
    detail := Detail
}}) ->
    {sagapgo_ConstraintViolated, Message, Constraint, Detail};
convert_error({pgsql_error, #{code := Code, message := Message}}) ->
    {sagapgo_PostgresqlError, Code, <<"unknown">>, Message};
convert_error(#{
    error := badarg_encoding,
    type_info := #{name := Expected},
    value := Value
}) ->
    Got = list_to_binary(io_lib:format("~p", [Value])),
    {sagapgo_UnexpectedArgumentType, Expected, Got};
convert_error(closed) ->
    {sagapgo_QueryTimeout};
convert_error(Other) ->
    {sagapgo_PostgresqlError, <<"unknown">>, <<"unknown">>, list_to_binary(io_lib:format("~p", [Other]))}.
