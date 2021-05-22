defmodule Dixit.Player do
  @moduledoc """
  Receives messages from the websocket library and sends them to the logic,
  and vice versa.
  """

  require Logger

  use Bitwise
  use GenServer, restart: :temporary

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    Logger.info("Hello from a player")

    with :ok <- if(args.ws?, do: handshake(args.socket), else: :ok),
         # Move to active mode and raw packets after the handshake
         :ok <- :inet.setopts(args.socket, packet: :raw, active: true)
    do
      {:ok, Map.put(args, :buffer, "")}
    else
      {:error, err} -> {:stop, err}
    end
  end

  # Received a message from the server
  @impl true
  def handle_call({:send, message}, _from, args) do
    send_message(message, args)
    {:reply, :ok, args}
  end

  @impl true
  def handle_call({:send, item, state, player}, _from, args) do
    send_message(Dixit.Command.format({item, state, player}), args)
    {:reply, :ok, args}
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
    Logger.debug(":recv #{message}")

    with {:ok, command} <- Dixit.Command.parse(message) do
      case Dixit.GameRegister.run(command) do
        {:ok, state, player} ->
          send_message(Dixit.Command.format_state(state, player, true), args)

        :ok ->
          :ok

        {:error, e} ->
          send_message("ERROR #{e}", args)
      end
    else
      {:error, e} -> send_message("ERROR #{e}", args)
    end
  end

  ## Network related functions

  # Do the websocket handshake
  defp handshake(socket, key \\ nil) do
    with {:ok, line} <- read_line(socket) do
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

        # Take note of the key
        "Sec-WebSocket-Key: " <> key      -> handshake(socket, key)

        # Open the connection
        "" ->
          if (key) do
            webSocketMagicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
            response =
              key
              |> (&(&1 <> webSocketMagicString)).()
              |> (&:crypto.hash(:sha, &1)).()
              |> Base.encode64()

            Logger.debug("Connecting")
            with :ok <- write_line("HTTP/1.1 101 Switching Protocols", socket),
                 :ok <- write_line("Upgrade: websocket", socket),
                 :ok <- write_line("Connection: Upgrade", socket),
                 :ok <- write_line("Sec-WebSocket-Accept: #{response}", socket),
                 :ok <- write_line("", socket) do
              :ok
            end
          else
            Logger.warn("No key provided, aborting.")
            {:error, :nokey}
          end

        # Ignore other headers
        _ ->
          Logger.warn("Unknown header: #{line}")
          handshake(socket, key)
      end
    end
  end

  # Read a single line in plain text (only used during the handshake)
  @spec read_line(port) :: {:ok, binary} | {:error, atom}
  defp read_line(socket) when is_port(socket) do
    with {:ok, data} <- :gen_tcp.recv(socket, 0) do
      data = String.trim(data)
      Logger.debug(":recv #{inspect(data)}")
      {:ok, data}
    end
  end

  # Write a single line in plain text
  @spec write_line(String.t(), port) :: :ok | {:error, atom}
  defp write_line(line, socket, terminator \\ "\r\n") when is_port(socket) do
    Logger.debug(":send " <> line)
    :gen_tcp.send(socket, line <> terminator)
  end

  @impl true
  def handle_info({:tcp, _, data}, args) do
    buffer = args.buffer <> data
    new_buffer =
      if args.ws? do
        case extract_frame(buffer) do
          {:incomplete_frame, buffer} ->
            buffer

          {:ok, {:text_frame, message, buffer}} ->
            deal_with_message(message, args)
            buffer

          {:ok, {:closing_frame, _message, buffer}} ->
            Logger.info("Received closing frame");
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

  def handle_info({:tcp_closed, _}, args) do
    Logger.warn("Client closed TCP connection")
    {:stop, :normal, args}
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
    decode(
      rest,
      mtail <> <<mhead>>,
      acc <> <<byte ^^^ mhead>>
    )
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
  @spec extract_frame(binary, boolean) ::
          {:ok, {atom, binary, binary}}
          | {:incomplete_frame, binary}
          | {:invalid_frame, atom}
          | {:not_implemented_yet, atom}
  def extract_frame(buffer, mask_required \\ true) do
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
  @spec encode(binary) :: binary
  defp encode(data) do
    len = byte_size(data)

    cond do
      len <= 125   -> <<129, len>> <> data
      len <= 65536 -> <<129, 126, len::16>> <> data
      # Technically incorrect for messages larger than ~9 EiB...
      true         -> <<129, 127, len::64>> <> data
    end
  end

  # Send data as a websocket packet
  @spec write_packet(binary, port) :: :ok | {:error, atom}
  defp write_packet(data, socket) when is_port(socket) do
    Logger.debug(":s #{data}")
    :gen_tcp.send(socket, encode(data))
  end
end
