defmodule Dixit.Player do
  @moduledoc """
  Receives messages from the websocket library and sends them to the logic,
  and vice versa.
  """

  require Logger

  use Bitwise
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    Logger.info("Hello from a player")
    if args.ws? do
      handshake(args.socket)
    end
    # Move to active mode and raw packets after the handshake
    :inet.setopts(args.socket, packet: :raw, active: true)
    {:ok, Map.put(args, :buffer, "")}
  end

  # Received a message from the server
  @impl true
  def handle_call({:send, message}, _from, args) do
    send_message(message, args)
    {:reply, :ok, args}
  end

  @impl true
  def handle_call({:send_state, state}, _from, args) do
    send_message(Dixit.Command.format_state(state), args)
    {:reply, :ok, args}
  end

  defp send_commands(command, args) do
    cond do
      is_list(command) -> Enum.each(command, &send_commands(&1, args))
      true -> send_message(Dixit.Command.format(command), args)
    end
  end

  def send_command(command, id) do
    message = Dixit.Command.format(command)
    GenServer.call(id, {:send, message})
  end

  def send_message(data, args) do
    cond do
      is_list(data) -> Enum.each(data, &send_message(&1, args))
      args.ws?      -> write_packet(data, args.socket)
      true          -> write_line(data, args.socket)
    end
  end

  # Received a message from the player
  def deal_with_message(message, args) do
    Logger.debug(":r #{message}")
    with {:ok, command}     <- Dixit.Command.parse(message),
         {:ok, state, hand} <- Dixit.GameRegister.run(command) do
      send_message(Dixit.Command.format_state(state), args)
      if hand !== nil && hand !== true, do: send_commands({:cards, hand}, args)
      :ok
    else
      {:error, e} -> send_message("ERROR #{e}", args)
    end
  end

  
  ## Network related functions

  # Do the websocket handshake
  defp handshake(socket, key \\ nil) do
    line = read_line(socket)
    case line do
      # Ignore known headers
      "GET / HTTP/1.1"                  -> handshake(socket, key)
      "Host: " <> _                     -> handshake(socket, key)
      "Connection: Upgrade"             -> handshake(socket, key)
      "Connection: keep-alive, Upgrade" -> handshake(socket, key)
      "Upgrade: websocket"              -> handshake(socket, key)
      "Pragma: no-cache"                -> handshake(socket, key)
      "Cache-Control: no-cache"         -> handshake(socket, key)
      "User-Agent: " <> _               -> handshake(socket, key)
      "Origin: " <> _                   -> handshake(socket, key)
      "Accept-Encoding: " <> _          -> handshake(socket, key)
      "Accept-Language: " <> _          -> handshake(socket, key)
      "Accept: " <> _                   -> handshake(socket, key)
      "Sec-WebSocket-Version: 13"       -> handshake(socket, key)
      "Sec-WebSocket-Extensions: " <> _ -> handshake(socket, key)

      # Remember the key
      "Sec-WebSocket-Key: " <> key      -> handshake(socket, key)

      "" ->  # Open the connection
        webSocketMagicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        response =
          key
          |> (&(&1 <> webSocketMagicString)).()
          |> (&(:crypto.hash(:sha, &1))).()
          |> Base.encode64()

        Logger.debug("Connecting")
        write_line("HTTP/1.1 101 Switching Protocols", socket)
        write_line("Upgrade: websocket", socket)
        write_line("Connection: Upgrade", socket)
        write_line("Sec-WebSocket-Accept: #{response}", socket)
        write_line("", socket)

      _ ->  # Ignore other headers
        Logger.debug("Unknown header: #{line}")
        handshake(socket, key)
    end
  end

  # Read a single line in plain text (only used during the handshake)
  defp read_line(socket) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    data = String.trim(data)
    Logger.debug(":recv #{inspect data}", pid: self())
    data
  end

  # Write a single line in plain text
  defp write_line(line, socket, terminator \\ "\r\n") do
    Logger.debug(":send #{line}")
    :gen_tcp.send(socket, "#{line}#{terminator}")
  end

  @impl true
  def handle_info({:tcp, _, data}, args) do
    buffer = args.buffer <> data
    new_buffer = if args.ws? do
      case extract_frame(buffer) do
        {:incomplete_frame, buffer} ->
          buffer

        {:ok, {:text_frame, message, buffer}} ->
          deal_with_message(message, args)
          buffer
      end
    else
      case String.split(buffer, "\r\n", parts: 2) do
        [buffer] -> # Incomplete message
          buffer

        [message, buffer] ->
          deal_with_message(message, args)
          buffer
      end
    end
    {:noreply, %{args | buffer: new_buffer}}
  end

  # Decode masked data
  defp decode(payload, mask, acc \\ "")

  defp decode(payload, "", _) do
    payload
  end
  
  defp decode("", _, acc) do
    acc
  end

  defp decode(<<byte, rest::binary>>, <<mhead, mtail::binary>>, acc) do
    decode(rest,
      mtail <> <<mhead>>,
      acc <> <<byte ^^^ mhead>>)
  end

  @doc """
  Extract the first WebSocket frame from the buffer.
  Returns either
  - {:ok, frame, rest_of_buffer}
  - :incomplete_frame
  - {:invalid_frame, :reason}
  - {:not_implemented_yet, :feature}

  ## Examples

    iex> extract_frame("")
    {:incomplete_frame, ""}

    iex> extract_frame(<<0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f, ?r, ?e, ?s, ?t>>, false)
    {:ok, {:text_frame, "Hello", "rest"}}
    
    iex> extract_frame(<<0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58>>)
    {:ok, {:text_frame, "Hello", ""}}
  """
  defp extract_frame(buffer, mask_required \\ true) do
    with <<fin::1, rsv::3, opcode::4, mask?::1, len::7, buffer::binary>> <- buffer,
         len_size = %{126 => 2, 127 => 8}[len] || 0,
         <<new_len::binary-size(len_size), buffer::binary>> <- buffer,
         len = if(len_size > 0, do: new_len, else: len),
         mask_size = if(mask? == 1, do: 4, else: 0),
         <<mask::binary-size(mask_size), payload::binary-size(len), buffer::binary>> <- buffer do
      message = decode(payload, mask)
      cond do
        fin == 0     -> {:not_implemented_yet, :continuation_frame}
        rsv != 0     -> {:invalid_frame, :rsv_non_zero}
        mask? == 0 && mask_required
                     -> {:invalid_frame, :no_mask}
        opcode == 0  -> {:not_implemented_yet, :continuation_frame}
        opcode == 1  -> {:ok, {:text_frame, message, buffer}}
        opcode == 2  -> {:ok, {:binary_frame, message, buffer}}
        opcode == 8  -> {:ok, {:closing_frame, message, buffer}}
        opcode == 9  -> {:ok, {:ping_frame, message, buffer}}
        opcode == 10 -> {:ok, {:pong_frame, message, buffer}}
        true         -> {:invalid_frame, :invalid_opcode}
      end
    else
      _ -> {:incomplete_frame, buffer}
    end
  end

  # Encode data into a packet
  defp encode(data) do
    len = byte_size(data)
    cond do
      len <= 125   -> <<129, len>> <> data
      len <= 65536 -> <<129, 126, len::16>> <> data
      # Technically incorrect for messages larger than ~10 EiB...
      true         -> <<129, 127, len::64>> <> data
    end
  end

  # Send data as a websocket packet
  defp write_packet(data, socket) do
    Logger.debug(":s #{data}")
    :gen_tcp.send(socket, encode(data))
  end
end
