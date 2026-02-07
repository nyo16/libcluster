defmodule Cluster.Strategy do
  @moduledoc """
  This module defines the behaviour for implementing clustering strategies.

  ## Telemetry

  The following telemetry events are emitted by libcluster:

  ### `[:libcluster, :connect_node, :ok]`

  Emitted when a node is successfully connected.

  * Measurements: `%{duration: integer}` (in native time units)
  * Metadata: `%{node: atom, topology: atom}`

  ### `[:libcluster, :connect_node, :error]`

  Emitted when a node connection fails.

  * Measurements: `%{duration: integer}` (in native time units)
  * Metadata: `%{node: atom, topology: atom, reason: term}`

  ### `[:libcluster, :disconnect_node, :ok]`

  Emitted when a node is successfully disconnected.

  * Measurements: `%{duration: integer}` (in native time units)
  * Metadata: `%{node: atom, topology: atom}`

  ### `[:libcluster, :disconnect_node, :error]`

  Emitted when a node disconnection fails.

  * Measurements: `%{duration: integer}` (in native time units)
  * Metadata: `%{node: atom, topology: atom, reason: term}`

  ### `[:libcluster, :poll, :start | :stop | :exception]`

  Emitted around each strategy's poll cycle using `:telemetry.span/3`.

  * Start measurements: `%{system_time: integer}`
  * Stop measurements: `%{duration: integer}`
  * Metadata: `%{topology: atom, strategy: module}`
  * Stop metadata adds: `%{nodes_discovered: integer}`

  ### `[:libcluster, :http_request, :start | :stop | :exception]`

  Emitted around HTTP requests in Kubernetes and Rancher strategies.

  * Start measurements: `%{system_time: integer}`
  * Stop measurements: `%{duration: integer}`
  * Metadata: `%{topology: atom, url: String.t()}`
  * Stop metadata adds: `%{status: integer}`
  """
  defmacro __using__(_) do
    quote do
      @behaviour Cluster.Strategy

      @impl true
      def child_spec(args) do
        %{id: __MODULE__, type: :worker, start: {__MODULE__, :start_link, [args]}}
      end

      defoverridable child_spec: 1
    end
  end

  @type topology :: atom
  @type bad_nodes :: [{node, reason :: term}]
  @type mfa_tuple :: {module, atom, [term]}
  @type strategy_args :: [Cluster.Strategy.State.t()]

  # Required for supervision of the strategy
  @callback child_spec(strategy_args) :: Supervisor.child_spec()
  # Starts the strategy
  @callback start_link(strategy_args) :: {:ok, pid} | :ignore | {:error, reason :: term}

  @doc """
  Given a list of node names, attempts to connect to all of them.
  Returns `:ok` if all nodes connected, or `{:error, [{node, reason}, ..]}`
  if we failed to connect to some nodes.

  All failures are logged.
  """
  @spec connect_nodes(topology, mfa_tuple, mfa_tuple, [atom()]) :: :ok | {:error, bad_nodes}
  def connect_nodes(topology, {_, _, _} = connect, {_, _, _} = list_nodes, nodes)
      when is_list(nodes) do
    {connect_mod, connect_fun, connect_args} = connect
    {list_mod, list_fun, list_args} = list_nodes
    ensure_exported!(list_mod, list_fun, length(list_args))
    current_node = Node.self()

    need_connect =
      nodes
      |> difference(apply(list_mod, list_fun, list_args))
      |> Enum.reject(fn n -> current_node == n end)

    bad_nodes =
      Enum.reduce(need_connect, [], fn n, acc ->
        fargs = connect_args ++ [n]
        ensure_exported!(connect_mod, connect_fun, length(fargs))

        start = System.monotonic_time()

        case apply(connect_mod, connect_fun, fargs) do
          true ->
            :telemetry.execute(
              [:libcluster, :connect_node, :ok],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology}
            )

            Cluster.Logger.info(topology, "connected to #{inspect(n)}")
            acc

          false ->
            :telemetry.execute(
              [:libcluster, :connect_node, :error],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology, reason: :unreachable}
            )

            Cluster.Logger.warning(topology, "unable to connect to #{inspect(n)}")
            [{n, false} | acc]

          :ignored ->
            :telemetry.execute(
              [:libcluster, :connect_node, :error],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology, reason: :not_part_of_network}
            )

            Cluster.Logger.warning(
              topology,
              "unable to connect to #{inspect(n)}: not part of network"
            )

            [{n, :ignored} | acc]
        end
      end)

    case bad_nodes do
      [] -> :ok
      _ -> {:error, bad_nodes}
    end
  end

  @doc """
  Given a list of node names, attempts to disconnect from all of them.
  Returns `:ok` if all nodes disconnected, or `{:error, [{node, reason}, ..]}`
  if we failed to disconnect from some nodes.

  All failures are logged.
  """
  @spec disconnect_nodes(topology, mfa_tuple, mfa_tuple, [atom()]) :: :ok | {:error, bad_nodes}
  def disconnect_nodes(topology, {_, _, _} = disconnect, {_, _, _} = list_nodes, nodes)
      when is_list(nodes) do
    {disconnect_mod, disconnect_fun, disconnect_args} = disconnect
    {list_mod, list_fun, list_args} = list_nodes
    ensure_exported!(list_mod, list_fun, length(list_args))
    current_node = Node.self()

    need_disconnect =
      nodes
      |> intersection(apply(list_mod, list_fun, list_args))
      |> Enum.reject(fn n -> current_node == n end)

    bad_nodes =
      Enum.reduce(need_disconnect, [], fn n, acc ->
        fargs = disconnect_args ++ [n]
        ensure_exported!(disconnect_mod, disconnect_fun, length(fargs))

        start = System.monotonic_time()

        case apply(disconnect_mod, disconnect_fun, fargs) do
          true ->
            :telemetry.execute(
              [:libcluster, :disconnect_node, :ok],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology}
            )

            Cluster.Logger.info(topology, "disconnected from #{inspect(n)}")
            acc

          false ->
            :telemetry.execute(
              [:libcluster, :disconnect_node, :error],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology, reason: :already_disconnected}
            )

            Cluster.Logger.warning(
              topology,
              "disconnect from #{inspect(n)} failed because we're already disconnected"
            )

            acc

          :ignored ->
            :telemetry.execute(
              [:libcluster, :disconnect_node, :error],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology, reason: :not_part_of_network}
            )

            Cluster.Logger.warning(
              topology,
              "disconnect from #{inspect(n)} failed because it is not part of the network"
            )

            acc

          reason ->
            :telemetry.execute(
              [:libcluster, :disconnect_node, :error],
              %{duration: System.monotonic_time() - start},
              %{node: n, topology: topology, reason: reason}
            )

            Cluster.Logger.warning(
              topology,
              "disconnect from #{inspect(n)} failed with: #{inspect(reason)}"
            )

            [{n, reason} | acc]
        end
      end)

    case bad_nodes do
      [] -> :ok
      _ -> {:error, bad_nodes}
    end
  end

  @doc """
  Wraps a strategy's poll cycle in a telemetry span.

  The given function should return a list of discovered nodes.
  Returns the list of nodes.
  """
  def poll_span(topology, strategy, fun) do
    :telemetry.span([:libcluster, :poll], %{topology: topology, strategy: strategy}, fn ->
      result = fun.()
      nodes_count = if is_list(result), do: length(result), else: 0
      {result, %{topology: topology, strategy: strategy, nodes_discovered: nodes_count}}
    end)
  end

  @doc false
  def http_request(topology, method, request, http_options, options) do
    {url, _headers} = request
    metadata = %{topology: topology, url: List.to_string(url)}

    :telemetry.span([:libcluster, :http_request], metadata, fn ->
      result = :httpc.request(method, request, http_options, options)

      status =
        case result do
          {:ok, {{_, code, _}, _, _}} -> code
          _ -> 0
        end

      {result, Map.put(metadata, :status, status)}
    end)
  end

  defp intersection(_a, []), do: []
  defp intersection([], _b), do: []

  defp intersection(a, b) when is_list(a) and is_list(b) do
    a |> MapSet.new() |> MapSet.intersection(MapSet.new(b))
  end

  defp difference(a, []), do: a
  defp difference([], _b), do: []

  defp difference(a, b) when is_list(a) and is_list(b) do
    a |> MapSet.new() |> MapSet.difference(MapSet.new(b))
  end

  defp ensure_exported!(mod, fun, arity) do
    unless function_exported?(mod, fun, arity) do
      raise "#{mod}.#{fun}/#{arity} is undefined!"
    end
  end
end
