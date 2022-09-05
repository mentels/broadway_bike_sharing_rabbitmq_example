defmodule BikeSharing do
  @moduledoc """
  This is an app that reads coordinates from bike sharing.

  A Broadway example using RabbitMQ that ingest coordinates and save them
  in the database for future processing.
  """

  use Broadway
  require Logger

  alias Broadway.Message
  alias BikeSharing.Repo
  alias BikeSharing.BikeCoordinate

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      # RabbitMQ producer will get given amount of message in advance (prefetch_count)
      # so that they can be immediately passed down to processors when available;
      # once a batch of messages gets acked a new batch, up to the prefetch is automatically sent
      producer: [
        module: Application.fetch_env!(:bike_sharing, :producer_module),
        concurrency: 2
      ],
      # each processor ask for `max_demand * producer_concurrency` initially
      #
      # it's bad when messages are enqueued in processors mailbox as the don't have a chance
      # to get redistributed to other processors that are available
      #
      # max_demand is set for ALL processors stages (in total or for each? I guess for each;
      # otherwise how would they "divide the demand"?)
      processors: [
        default: [concurrency: 4]
      ],
      batchers: [
        default: [batch_size: 5, batch_timeout: 1500, concurrency: 4],
        parse_err: [batch_size: 5, concurrency: 2, batch_timeout: 1500]
      ]
    )
  end

  @impl true
  def handle_message(_, %Message{} = message, _) do
    message =
      Message.update_data(message, fn data ->
        case String.split(data, ",") do
          [_, lat, lng, bike_id, _timestamp] ->
            lat = String.to_float(lat)
            lng = String.to_float(lng)

            %{bike_id: String.to_integer(bike_id), point: %Geo.Point{coordinates: {lat, lng}}}

          _ ->
            data
        end
      end)

    if is_binary(message.data) do
      # Move the message to a batcher of errors.
      Message.put_batcher(message, :parse_err)
    else
      message
    end
  end

  @impl true
  def handle_batch(:default, messages, _, _) do
    Logger.debug("in default batcher")
    Logger.debug(fn -> "size: #{length(messages)}" end)
    Enum.map(messages, &Logger.debug("message: #{inspect(&1.data)}"))

    {rows, _} =
      Repo.insert_all(
        BikeCoordinate,
        Enum.map(messages, &Map.put(&1.data, :inserted_at, DateTime.utc_now()))
      )

    Logger.debug("saved rows: #{rows}")

    messages
  end

  def handle_batch(:parse_err, messages, _, _) do
    Logger.info("in parse error batcher")
    Logger.info(fn -> "size: #{length(messages)}" end)
    Logger.info("the following messages with errors will be dropped")

    Enum.map(messages, &Logger.info("message: #{inspect(&1.data)}"))

    messages
  end
end
