defmodule Dixit.Player do
  @moduledoc """
  Utility functions to communicate with the clients.
  """

  @webSocketMagicString "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  @webSockets false

  require Logger
  use Bitwise

  def connect(socket) do
    if (@webSockets) do
      handshake(socket)
    end
    serve(socket)
  end
  
  def serve(socket) do
    data = read_command(socket)
    case Dixit.Command.parse(data) do
      {:ok, command} ->
        case Dixit.Command.run(command, socket) do
          {:error, e} -> write_command("ERROR #{e}", socket)
          _ -> nil
        end
      {:error, e} -> write_command("ERROR #{e}", socket)
    end
    serve(socket)
  end

  defp read_command(socket) do
    if (@webSockets) do
      read_packet(socket)
    else
      read_line(socket)
    end
  end

  def write_command(data, socket) do
    if (is_list(data)) do
      Enum.each(data, &write_command(&1, socket))
    else
      if (@webSockets) do
        write_packet(data, socket)
      else
        write_line(data, socket)
      end
    end
  end
  
  # Read a single line in plain text
  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data = String.trim_trailing(data)
    IO.puts(":recv " <> data)
    data
  end

  @doc "Write a single line in plain text"
  def write_line(line, socket, terminator \\ "\r\n") do
    IO.puts(":send #{line}#{terminator}")
    :gen_tcp.send(socket, "#{line}#{terminator}")
  end

  @doc "Do the websocket handshake"
  def handshake(socket, response \\ nil) do
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

  # Read a websocket packet
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
  def write_packet(data, socket) do
    IO.puts(":s #{data}")
    :gen_tcp.send(socket, encode(data))
  end
end
