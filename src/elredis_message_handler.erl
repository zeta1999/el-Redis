-module(elredis_message_handler).

-export([process_message/1]).
%replies
% status: +
% bulk $
% multi bulk *

-define(NL, "\r\n").

process_message(RawCommand) ->
  case binary:split(RawCommand,<<?NL>>) of
    [<<$*,LengthBin/binary>>, Buffer] -> 
      Length = list_to_integer(binary_to_list(LengthBin)), 
      %Commands = split_commands(Rest),
      case do_process_bulk_message(Length, Buffer) of
        {ok, Arguments, _Overflow} -> 
          io:format("response ~p ~n",[Arguments]),
          process_bulk_message(Length, Arguments)
      end;
    _ -> process_bulk_message(1,error)
  end.

do_process_bulk_message(Length, Buffer) ->
  do_process_bulk_message(Length, Buffer, []).

do_process_bulk_message(0, Rest, Arguments) ->
  {ok,reverse_list_and_uppercase_command(Arguments), Rest};
do_process_bulk_message(Length, Buffer, Arguments) ->
  {ok, Value, Rest} = process_bulk_message2(Length,Buffer),
  do_process_bulk_message(Length - 1, Rest, [Value | Arguments]).

process_bulk_message2(_NoOfArguments, Buffer) ->
  case argument_length(Buffer) of
    Length ->

      if Length =:= -1 -> error; 
      
      size(Buffer) - (size(<<?NL>>) * 2) >= Length ->
          io:format("buffer ~p ~n", [Buffer]),
          ArgPositions = length(integer_to_list(Length)) + 1, %include $
        <<_ArgumentDesc:ArgPositions/binary,?NL, Value:Length/binary, ?NL, Rest/binary>>  = Buffer,
        {ok, binary_to_list(Value), Rest};
      
      true -> error %incomplete
    end
  end.

argument_length(Buffer) ->
  case binary:split(Buffer, <<?NL>>) of
    [<<$$, LengthBin/binary>>, Rest] -> list_to_integer(binary_to_list(LengthBin));
    _ -> error
   end.


        




%await_length(Buffer) ->                                                 
%    case binary:split(Buffer, <<"\r\n">>) of                                    
%        %% Found CRLF and correct line prefix for length.                       
%        [<<"$", LengthBin/binary>>, Buffer2] ->                                 
%            Length = list_to_integer(binary_to_list(LengthBin)),                
%            await_message(Length, Buffer2);                             
%        %% Found CRLF but not the expected line prefix for the length.          
%        [Line, _Buffer2] ->                                                      
%            erlang:error(badarg, [Line]);                                       
%        %% No CRLF found, read more data and retry. Possibly close              
%        %% connection if buffer is larger than expected.                        
%        [_Buffer] ->                                                            
%            ok
%            %% TODO - handle errors that we can handle.                         
%            %{ok, Packet} = gen_tcp:recv(Socket, 0, 5000),                       
%            %await_length(<<Buffer/binary, Packet/binary>>)              
%    end.

split_commands(Buffer) ->
  split_commands(Buffer,[]).

split_commands(Buffer, Commands) ->
  case binary:split(Buffer,<<?NL>>) of
    [<<"$",_CommandLengthBin/binary>>, Buffer2] -> split_commands(Buffer2, Commands);
    [NewCommand, Buffer2] -> split_commands(Buffer2, [binary_to_list(NewCommand) | Commands]);
    [_EmptyBuffer] -> reverse_list_and_uppercase_command(Commands)
  end.

reverse_list_and_uppercase_command(Commands) ->
   [Head | Tail] = lists:reverse(Commands),
   [string:to_upper(Head) | Tail].

create_reply_for(bulk,RawResponse) ->
  create_reply_for(bulk, RawResponse, []).

create_reply_for(bulk, [], Response) ->
  list_to_binary(lists:reverse(Response));
create_reply_for(bulk, [Head | Tail], Response) ->
  Msg = lists:concat(["$",length(Head),?NL,Head,?NL]), 
  create_reply_for(bulk, Tail, [Msg | Response]).

process_bulk_message(1, ["PING"]) ->
  {send, <<"+PONG\r\n">>};
process_bulk_message(1,["INFO"]) ->
  {send, <<"+elredis:0.0.1\r\n\r\n">>};
process_bulk_message(3,["SET",Key, Value]) ->
  Response = case elredis_db:set(Key, Value) of
    ok -> <<"+OK\r\n">>;
    _ -> <<"-error occured">>
  end,
  {send, Response};
process_bulk_message(2,["GET",Key]) ->
  Value = elredis_db:lookup(Key),
  {send, create_reply_for(bulk, [Value])};
process_bulk_message(_, _) ->
  {send, <<"-ERR Unknown or disabled command\r\n">>}.


