# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

libcluster is an Elixir library for automatic Erlang cluster formation and management. It provides a pluggable strategy system for node discovery and connection, with built-in strategies for Epmd, Gossip (multicast UDP), Kubernetes (metadata API and DNS), Rancher, and more.

## Common Commands

- **Run all tests:** `mix test`
- **Run a single test file:** `mix test test/epmd_test.exs`
- **Run a specific test:** `mix test test/epmd_test.exs:42`
- **Check formatting:** `mix format --check-formatted`
- **Format code:** `mix format`
- **Get dependencies:** `mix deps.get`
- **Check unused deps:** `mix deps.get && mix deps.unlock --check-unused`
- **Run dialyzer:** `mix dialyzer`

## Architecture

### Core Components

- **`Cluster.Supervisor`** (`lib/supervisor.ex`) — Entry point. Takes a topology keyword list, builds a `Cluster.Strategy.State` for each topology, and supervises one strategy process per topology under `:one_for_one`.

- **`Cluster.Strategy`** (`lib/strategy/strategy.ex`) — Behaviour module defining `start_link/1` and `child_spec/1` callbacks. Also provides `connect_nodes/4` and `disconnect_nodes/4` helpers that strategies call to manage cluster membership. These helpers handle node diffing, telemetry events (`[:libcluster, :connect_node, ...]` / `[:libcluster, :disconnect_node, ...]`), and logging.

- **`Cluster.Strategy.State`** (`lib/strategy/state.ex`) — Struct passed to every strategy containing: `topology` (name atom), `connect`/`disconnect`/`list_nodes` (MFA tuples, defaulting to Distributed Erlang), `config` (strategy-specific keyword list), and `meta` (strategy-managed runtime state).

### Writing a Strategy

Strategies `use Cluster.Strategy` and are typically GenServers. The pattern:
1. `start_link/1` receives `[%Cluster.Strategy.State{}]`
2. Use `state.config` for strategy-specific options
3. Call `Cluster.Strategy.connect_nodes/4` and `disconnect_nodes/4` for cluster management
4. Store runtime state in `state.meta`

### Connect/Disconnect Plumbing

Topology config can override `connect`, `disconnect`, and `list_nodes` MFA tuples to use alternatives to Distributed Erlang (e.g., Partisan). The default MFAs are `{:net_kernel, :connect_node, []}`, `{:erlang, :disconnect_node, []}`, and `{:erlang, :nodes, [:connected]}`.

### Test Support

- `test/support/` is compiled only in test env (`elixirc_paths` in mix.exs)
- `Cluster.Nodes` (`test/support/nodes.ex`) provides mock connect/disconnect/list_nodes functions that send messages to a caller process for assertion
- Kubernetes tests use ExVCR cassettes for HTTP API mocking
- Debug logging is controlled via `Application.get_env(:libcluster, :debug)`

## CI

Tests run against Elixir 1.13/OTP 22 and Elixir 1.17/OTP 27. Formatting and unused dep checks run only on the newer version.
