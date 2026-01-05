defmodule Play.PageMetadata do
  @moduledoc """
  Fetches page metadata and content from URLs using the CrazyEgg page metadata API.

  This module provides functionality to extract structured data from web pages including:
  - Page title and description
  - Canonical URL
  - Extracted text content

  The API renders pages and extracts content, handling JavaScript-rendered pages properly.
  """

  require Logger

  @default_base_url "https://page-metadata-api.crazyegg.com"

  @doc """
  Fetches metadata and content from the given URL.

  ## Options

  - `:device` - Device type for rendering, either "desktop" (default) or "mobile"

  ## Returns

  - `{:ok, map}` - Map containing title, description, canonical_url, and text content
  - `{:error, reason}` - Error tuple with reason

  ## Examples

      iex> Play.PageMetadata.fetch("https://example.com")
      {:ok, %{
        "title" => "Example Domain",
        "description" => "...",
        "canonical_url" => "https://example.com",
        "text" => "Example Domain\\nThis domain is for use..."
      }}
  """
  @max_refresh_retries 20

  def fetch(url, opts \\ []) do
    do_fetch(url, opts, 0)
  end

  defp do_fetch(url, opts, retries) do
    device = Keyword.get(opts, :device, "desktop")

    # Request both html and text extraction like the reference implementation
    body = %{
      url: url,
      device: device,
      extract: %{html: true, text: true}
    }

    if retries == 0, do: Logger.info("Fetching page metadata for: #{url}")

    :play
    |> Application.get_env(__MODULE__, base_url: @default_base_url)
    |> Keyword.merge(url: "/", json: body, retry: false, receive_timeout: 30_000)
    |> Req.new()
    |> Req.post()
    |> handle_response(url, opts, retries)
  end

  defp handle_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "refreshing"}}},
         url,
         opts,
         retries
       )
       when retries < @max_refresh_retries do
    Logger.debug(
      "Page metadata refreshing, retrying in 100ms... (#{retries + 1}/#{@max_refresh_retries})"
    )

    :timer.sleep(100)
    do_fetch(url, opts, retries + 1)
  end

  defp handle_response(
         {:ok, %Req.Response{status: 200, body: %{"status" => "refreshing"}}},
         _url,
         _opts,
         _retries
       ) do
    Logger.warning("Page metadata refresh timeout after #{@max_refresh_retries} retries")
    {:error, "Refresh timeout - page metadata not ready after 2 seconds"}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}, url, _opts, _retries) do
    {:ok, expand_s3_urls(body, url)}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, _url, _opts, _retries) do
    Logger.warning("Page metadata API error (#{status}): #{inspect(body)}")
    {:error, "API error (#{status}): #{inspect(body)}"}
  end

  defp handle_response({:error, reason}, _url, _opts, _retries) do
    Logger.warning("Page metadata request failed: #{inspect(reason)}")
    {:error, "Request failed: #{inspect(reason)}"}
  end

  defp expand_s3_urls(%{"data" => data} = body, original_url) do
    # First extract basic metadata
    metadata = extract_metadata(body)

    # Check if text is already present in the response
    case Map.get(data, "text") do
      text when is_binary(text) and text != "" ->
        # Text already in response, use it directly
        metadata

      _ ->
        # Try to fetch text from S3 URL
        text_url = data["text_url"]

        case text_url do
          nil ->
            Logger.debug("No text_url found in response, fetching raw HTML")
            fetch_and_extract_text(metadata, original_url)

          url ->
            case fetch_s3_content(url) do
              nil ->
                # S3 content not available, fall back to fetching raw HTML
                fetch_and_extract_text(metadata, original_url)

              html_content ->
                # S3 returns HTML source, extract text from it
                text = extract_text_from_html(html_content)
                title = extract_title_from_html(html_content)
                description = extract_meta_description(html_content)

                metadata
                |> maybe_put("text", text)
                |> maybe_put("title", title)
                |> maybe_put("description", description)
            end
        end
    end
  end

  defp expand_s3_urls(body, original_url) do
    # No data key, try to fetch raw HTML
    metadata = extract_metadata(body)
    fetch_and_extract_text(metadata, original_url)
  end

  defp extract_metadata(%{"data" => data}) do
    %{
      "title" => Map.get(data, "title", ""),
      "description" => Map.get(data, "description", ""),
      "canonical_url" => Map.get(data, "canonical_url", ""),
      "text" => Map.get(data, "text", ""),
      "screenshot_url" => Map.get(data, "screenshot_url"),
      "thumbnail_url" => Map.get(data, "thumbnail_url"),
      "device" => Map.get(data, "device"),
      "refreshed_at" => Map.get(data, "refreshed_at")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_metadata(_body) do
    %{
      "title" => "",
      "description" => "",
      "canonical_url" => "",
      "text" => ""
    }
  end

  # Fallback: fetch raw HTML from the original URL and extract text
  defp fetch_and_extract_text(metadata, url) do
    Logger.debug("Fetching raw HTML from: #{url}")

    # Use browser-like headers to avoid being blocked by news sites
    headers = [
      {"user-agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"},
      {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
      {"accept-language", "en-US,en;q=0.5"},
      {"accept-encoding", "gzip, deflate"},
      {"connection", "keep-alive"},
      {"upgrade-insecure-requests", "1"}
    ]

    case Req.get(url, headers: headers, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        text = extract_text_from_html(body)
        title = extract_title_from_html(body)
        description = extract_meta_description(body)

        metadata
        |> maybe_put("text", text)
        |> maybe_put("title", title)
        |> maybe_put("description", description)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Failed to fetch raw HTML (#{status})")
        metadata

      {:error, reason} ->
        Logger.warning("Raw HTML fetch failed: #{inspect(reason)}")
        metadata
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Extract text content from HTML by removing scripts, styles, and other non-content elements
  defp extract_text_from_html(html) do
    html
    # Remove script tags and their content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/ims, "")
    # Remove style tags and their content
    |> String.replace(~r/<style[^>]*>.*?<\/style>/ims, "")
    # Remove SVG tags and their content
    |> String.replace(~r/<svg[^>]*>.*?<\/svg>/ims, "")
    # Remove noscript tags and their content
    |> String.replace(~r/<noscript[^>]*>.*?<\/noscript>/ims, "")
    # Remove iframe tags
    |> String.replace(~r/<iframe[^>]*>.*?<\/iframe>/ims, "")
    # Remove head section entirely
    |> String.replace(~r/<head[^>]*>.*?<\/head>/ims, "")
    # Remove HTML comments
    |> String.replace(~r/<!--.*?-->/ms, "")
    # Remove all remaining HTML tags
    |> String.replace(~r/<[^>]+>/, " ")
    # Decode HTML entities
    |> decode_html_entities()
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    # Clean up excessive newlines
    |> String.replace(~r/\n\s*\n+/, "\n\n")
    |> String.trim()
  end

  # Extract title from HTML
  defp extract_title_from_html(html) do
    case Regex.run(~r/<title[^>]*>([^<]*)<\/title>/i, html) do
      [_, title] -> String.trim(title) |> decode_html_entities()
      _ -> nil
    end
  end

  # Extract meta description from HTML
  defp extract_meta_description(html) do
    case Regex.run(~r/<meta[^>]*name=["']description["'][^>]*content=["']([^"']*)["']/i, html) do
      [_, desc] ->
        String.trim(desc) |> decode_html_entities()

      _ ->
        # Try alternate order (content before name)
        case Regex.run(~r/<meta[^>]*content=["']([^"']*)["'][^>]*name=["']description["']/i, html) do
          [_, desc] -> String.trim(desc) |> decode_html_entities()
          _ -> nil
        end
    end
  end

  # Decode common HTML entities
  defp decode_html_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&#x2F;", "/")
    |> String.replace("&mdash;", "—")
    |> String.replace("&ndash;", "–")
    |> String.replace("&hellip;", "…")
    |> String.replace("&copy;", "©")
    |> String.replace("&reg;", "®")
    |> String.replace("&trade;", "™")
  end

  defp fetch_s3_content(url) when is_binary(url) do
    Logger.debug("Fetching S3 content from: #{url}")

    # Disable automatic decompression - S3 stores gzipped files as-is
    case Req.get(url, receive_timeout: 15_000, decode_body: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        # Content is gzipped, decompress it
        try do
          :zlib.gunzip(body)
        rescue
          _ ->
            # Not gzipped or decompression failed, return as-is
            body
        end

      {:ok, %Req.Response{status: status}} when status in [403, 404] ->
        # S3 content doesn't exist - this is expected in some environments
        Logger.debug("S3 content not available (#{status})")
        nil

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Unexpected S3 response (#{status})")
        nil

      {:error, reason} ->
        Logger.warning("S3 content fetch failed: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_s3_content(_), do: nil
end
