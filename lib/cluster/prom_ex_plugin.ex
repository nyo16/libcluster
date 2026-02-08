if Code.ensure_loaded?(PromEx.Plugin) do
  defmodule Cluster.PromExPlugin do
    @moduledoc """
    A PromEx plugin that exposes all libcluster telemetry events as Prometheus metrics.

    This module only compiles when `prom_ex` is available as a dependency.

    ## Usage

    Add this plugin to your PromEx module:

        defmodule MyApp.PromEx do
          use PromEx, otp_app: :my_app

          @impl true
          def plugins do
            [
              ...,
              Cluster.PromExPlugin
            ]
          end
        end

    ## Metrics

    ### Connect/Disconnect

    * `libcluster.connect_node.total` - Counter of successful node connections
    * `libcluster.connect_node.duration.milliseconds` - Distribution of connection durations
    * `libcluster.connect_node.error.total` - Counter of failed node connections
    * `libcluster.disconnect_node.total` - Counter of successful node disconnections
    * `libcluster.disconnect_node.error.total` - Counter of failed node disconnections

    ### Poll (requires poll telemetry instrumentation)

    * `libcluster.poll.duration.milliseconds` - Distribution of poll cycle durations
    * `libcluster.poll.nodes_discovered` - Last value of nodes discovered per poll
    * `libcluster.poll.exception.total` - Counter of poll exceptions

    ### HTTP Request (requires http_request telemetry instrumentation)

    * `libcluster.http_request.duration.milliseconds` - Distribution of HTTP request durations
    * `libcluster.http_request.total` - Counter of HTTP requests
    * `libcluster.http_request.exception.total` - Counter of HTTP request exceptions
    """

    use PromEx.Plugin

    @impl true
    def event_metrics(_opts) do
      [
        connect_disconnect_metrics(),
        poll_metrics(),
        http_request_metrics()
      ]
    end

    defp connect_disconnect_metrics do
      Event.build(:libcluster_connect_disconnect_event_metrics, [
        counter(
          [:libcluster, :connect_node, :total],
          event_name: [:libcluster, :connect_node, :ok],
          tags: [:topology, :node]
        ),
        distribution(
          [:libcluster, :connect_node, :duration, :milliseconds],
          event_name: [:libcluster, :connect_node, :ok],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:topology]
        ),
        counter(
          [:libcluster, :connect_node, :error, :total],
          event_name: [:libcluster, :connect_node, :error],
          tags: [:topology, :reason]
        ),
        counter(
          [:libcluster, :disconnect_node, :total],
          event_name: [:libcluster, :disconnect_node, :ok],
          tags: [:topology, :node]
        ),
        counter(
          [:libcluster, :disconnect_node, :error, :total],
          event_name: [:libcluster, :disconnect_node, :error],
          tags: [:topology, :reason]
        )
      ])
    end

    defp poll_metrics do
      Event.build(:libcluster_poll_event_metrics, [
        distribution(
          [:libcluster, :poll, :duration, :milliseconds],
          event_name: [:libcluster, :poll, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:topology, :strategy]
        ),
        last_value(
          [:libcluster, :poll, :nodes_discovered],
          event_name: [:libcluster, :poll, :stop],
          measurement: :nodes_discovered,
          tags: [:topology, :strategy]
        ),
        counter(
          [:libcluster, :poll, :exception, :total],
          event_name: [:libcluster, :poll, :exception],
          tags: [:topology, :strategy]
        )
      ])
    end

    defp http_request_metrics do
      Event.build(:libcluster_http_request_event_metrics, [
        distribution(
          [:libcluster, :http_request, :duration, :milliseconds],
          event_name: [:libcluster, :http_request, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:topology, :status]
        ),
        counter(
          [:libcluster, :http_request, :total],
          event_name: [:libcluster, :http_request, :stop],
          tags: [:topology, :status]
        ),
        counter(
          [:libcluster, :http_request, :exception, :total],
          event_name: [:libcluster, :http_request, :exception],
          tags: [:topology]
        )
      ])
    end
  end
end
