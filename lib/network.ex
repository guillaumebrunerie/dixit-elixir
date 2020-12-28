defmodule Dixit.Network do
  @moduledoc """
  Utility functions to communicate with the clients.
  """

  @webSocketMagicString "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  use Bitwise
  
  def init(args) do
    if args.ws? do
      handshake(args.socket)
    end
    read_next_message(args)
  end

  
  defp read_next_message(args) do
    IO.puts("Listening")
    message = if args.ws? do
      read_packet(args.socket)
    else
      read_line(args.socket)
    end

    case GenServer.call(args.parent, {:received, message}) do
      :ok -> :ok
      {:error, e} -> send_message("ERROR #{e}", args)
    end

    read_next_message(args)
  end

  def send_message(data, args) do
    if (is_list(data)) do
      Enum.each(data, &send_message(&1, args))
    else
      if args.ws? do
        write_packet(data, args.socket)
      else
        write_line(data, args.socket)
      end
    end
  end


  # Read a single line in plain text
  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data = String.trim_trailing(data)
    IO.puts(":recv #{inspect data}")
    data
  end

  # Write a single line in plain text
  defp write_line(line, socket, terminator \\ "\r\n") do
    IO.puts(":send #{line}#{terminator}")
    :gen_tcp.send(socket, "#{line}#{terminator}")
  end


  # Do the websocket handshake
  defp handshake(socket, response \\ nil) do
    line = read_line(socket)
    case line do
      "Sec-WebSocket-Key: " <> key ->  # Decode the key
        IO.puts("Received key")
        response =
          key
          |> (&(&1 <> @webSocketMagicString)).()
          |> (&(:crypto.hash(:sha,&1))).()
          |> Base.encode64()
        handshake(socket, response)

      "" ->  # Open the connection
        IO.puts("Connecting")
        write_line("HTTP/1.1 101 Switching Protocols", socket)
        write_line("Upgrade: websocket", socket)
        write_line("Connection: Upgrade", socket)
        write_line("Sec-WebSocket-Accept: #{response}", socket)
        write_line("", socket)
        :inet.setopts(socket, packet: :raw)
      _ ->  # Ignore other headers
        handshake(socket, response)
    end
  end
  

  # Read a websocket packet (basic)
  defp read_packet(socket) do
    {:ok, <<1::1, 0::3, 1::4, maskbit::1, len::7>>} = :gen_tcp.recv(socket, 2)
    {:ok, <<_::32>> = mask} = if maskbit, do: :gen_tcp.recv(socket, 4), else: {:ok, <<0::32>>}
    {:ok, payload} = :gen_tcp.recv(socket, len)
    data = decode(payload, mask)

    IO.puts(":r #{data}")
    data
  end            

  # Decode masked data
  defp decode(payload, mask, acc \\ "")
  
  defp decode("", _mask, acc) do
    acc
  end

  defp decode(<<byte, rest::binary>>, <<mhead, mtail::binary>>, acc) do
    decode(rest,
      mtail <> <<mhead>>,
      acc <> <<byte ^^^ mhead>>)
  end

  # Encode data into a packet
  defp encode(data) do
    len = byte_size(data)
    if (len >= 126), do: IO.puts("Unsupported packet size")
    <<129, len>> <> data
  end

  # Send data as a websocket packet
  defp write_packet(data, socket) do
    IO.puts(":s #{data}")
    :gen_tcp.send(socket, encode(data))
  end
end
