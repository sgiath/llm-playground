import Config

# WorkOS authentication
workos_client_id =
  System.get_env("WORKOS_CLIENT_ID") ||
    raise """
    environment variable WORKOS_CLIENT_ID is missing.
    Get it from your WorkOS dashboard at https://dashboard.workos.com
    """

workos_secret_key =
  System.get_env("WORKOS_SECRET_KEY") ||
    raise """
    environment variable WORKOS_SECRET_KEY is missing.
    Get it from your WorkOS dashboard at https://dashboard.workos.com
    """

config :sgiath_auth,
  workos_client_id: workos_client_id,
  workos_secret_key: workos_secret_key

# OpenRouter API configuration (used via LangChain's ChatOpenAI with custom endpoint)
openai_api_key =
  System.get_env("OPENAI_API_KEY") ||
    raise """
    environment variable OPENROUTER_API_KEY is missing.
    Get it from your OpenAI dashboard at https://openai.com
    """

anthropic_api_key =
  System.get_env("ANTHROPIC_API_KEY") ||
    raise """
    environment variable ANTHROPIC_API_KEY is missing.
    Get it from your Anthropic dashboard at https://anthropic.com
    """

google_ai_api_key =
  System.get_env("GEMINI_API_KEY") ||
    raise """
    environment variable GEMINI_API_KEY is missing.
    Get it from your Google Gemini dashboard at https://ai.google.com
    """

xai_api_key =
  System.get_env("XAI_API_KEY") ||
    raise """
    environment variable XAI_API_KEY is missing.
    Get it from your xAI dashboard at https://xai.com
    """

config :langchain,
  openai_key: openai_api_key,
  anthropic_key: anthropic_api_key,
  google_ai_key: google_ai_api_key,
  grok_key: xai_api_key

if System.get_env("PHX_SERVER") do
  config :play, PlayWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :play, Play.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :play, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :play, PlayWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :sgiath_auth,
    callback_url: "https://#{host}/auth/callback",
    logout_return_to: "https://#{host}/"

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :play, Play.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
