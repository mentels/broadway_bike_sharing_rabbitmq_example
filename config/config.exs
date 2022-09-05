import Config

config :bike_sharing,
  ecto_repos: [BikeSharing.Repo]

config :bike_sharing, BikeSharing.Repo,
  migration_timestamps: [type: :utc_datetime_usec],
  hostname: "localhost",
  types: BikeSharing.PostgresTypes

config :bike_sharing,
  producer_module:
    {BroadwayRabbitMQ.Producer,
     [
       queue: "bikes_queue",
       qos: [
         # the max num of unacked messages
         #
         # To ensure that all processors in a given pipeline can receive messages,
         # the value should be set to at least `max_demand * <number of processors>`
         prefetch_count: 50
       ],
       on_failure: :reject_and_requeue
     ]}

inside_docker_compose? = File.exists?("/.dockerenv")

# Load special config for Docker compose environment
if inside_docker_compose? do
  import_config "docker_compose.exs"
end

import_config "#{Mix.env()}.exs"
