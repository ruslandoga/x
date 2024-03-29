import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :x, X.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "plausible_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :x, X.Ch.Repo,
  url: "http://localhost:8123/plausible_events_db",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :x, X.S3,
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin",
  url: "http://localhost:9000",
  # minio includes the port in canonical request
  host: "localhost:9000",
  region: "us-east-1"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :x, XWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zptZAwdIuAT37LTV8cq6Q7IcFO5vtq6lHWwOId9nmmTQwnWMU1zDeDcRO9ZzoC9I",
  server: false

config :x, Oban, testing: :manual

# In test we don't send emails.
config :x, X.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
