-module(ierl_backend_elixir).

-behaviour(jup_kernel_backend).


-export([
         init/1,
         do_execute/4,
         do_is_complete/3,
         do_complete/4,
         opt_spec/0,
         language/0
        ]).


-record(state, {
          bindings = [],
          modules
         }).


opt_spec() ->
    {
     "Simple Elixir backend",
     [
      {path, undefined, "elixir-path", string, "Elixir install root directory"}
     ]
    }.


language() ->
    elixir.


init(Args) ->
    ElixirPath = get_elixir_path(Args),
    ElixirAppPath = filename:join([ElixirPath, lib, elixir, ebin]),
    IExAppPath = filename:join([ElixirPath, lib, iex, ebin]),

    code:add_path(ElixirAppPath),
    code:add_path(IExAppPath),

    {ok, _} = application:ensure_all_started(elixir),

    % We have to make sure that the compiler is loaded, otherwise the initial
    % is_complete call will answer too slowly and Jupyter will think it was not
    % implemented.
    'Elixir.Code':string_to_quoted(":undefined"),

    #state{}.


do_execute(Code, _Publish, _Msg, State) ->
    try
        {Res, NewBindings} =
            'Elixir.Code':eval_string(Code, State#state.bindings),

        {{ok, Res}, State#state{bindings=NewBindings}}
    catch
        error:Error ->
            case Error of
                #{
                    '__struct__' := Type,
                    'description' := Reason
                } ->
                    {{error, Type, Reason,
                      ['Elixir.Exception':format(error, Error)]},
                     State};
                _ ->
                    {{error, error, Error, <<>>}, State}
            end
    end.


do_is_complete(Code, _Msg, State) ->
    Res = try
              'Elixir.Code':'string_to_quoted!'(Code),
              complete
          catch
              error:#{ '__struct__' := 'Elixir.TokenMissingError'} ->
                  incomplete;
              error:_Other ->
                  invalid
          end,

    {Res, State}.


do_complete(Code, CursorPos, _Msg, State) ->
    L = lists:sublist(binary_to_list(Code), CursorPos),
    Res = case 'Elixir.IEx.Autocomplete':expand(lists:reverse(L)) of
              {yes, Expansion, []} ->
                  [Expansion];
              {yes, [], Matches} ->
                  [
                   Name ||
                   {Name, _Arity} <- lists:map(fun split_arity/1, Matches)
                  ];
              {no, [], Matches} ->
                  [
                   Name ||
                   {Name, _Arity} <- lists:map(fun split_arity/1, Matches)
                  ]
          end,

    {[list_to_binary(R) || R <- Res], State}.


split_arity(Str) ->
    {Name, [_|Arity]} = lists:splitwith(fun (X) -> X =/= $/ end, Str),
    {Name, list_to_integer(Arity)}.


get_elixir_path(Args) ->
    case maps:find(path, Args) of
        error ->
            "c:/Program Files (x86)/Elixir";
        {ok, Value} ->
            Value
    end.
