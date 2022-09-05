require Logger
{interval_ms, ""} = "BIKE_INTERVAL" |> System.get_env("1000") |> Integer.parse()
{_, opts} = Application.fetch_env!(:bike_sharing, :producer_module)

# Wait for RabbitMQ connection on Docker
if File.exists?("/.dockerenv") do
  Process.sleep(5_000)
end

{:ok, connection} = AMQP.Connection.open(Keyword.get(opts, :connection, []))
{:ok, channel} = AMQP.Channel.open(connection)
AMQP.Queue.declare(channel, "bikes_queue", durable: true)

sample = File.read!("./priv/trajectories_sample.csv")
[_header | lines] = String.split(sample, "\n")

Logger.info("Processing lines_count=#{length(lines)} at interval=#{interval_ms} ms")
for line <- lines, do: Process.sleep(interval_ms) && AMQP.Basic.publish(channel, "", "bikes_queue", line)

AMQP.Connection.close(connection)
