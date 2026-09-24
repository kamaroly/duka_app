defmodule DukaApp.Requests.Attachments do
  @moduledoc """
  Files attached to payment requests, kept in `request_attachments/` in the
  app's data directory (see `DukaApp.DataDir`).

  A file is copied in as soon as the user adds it, so it stays readable
  after the camera or file picker cleans up its temporary copy. If the
  request is never sent, the form deletes what it copied.
  """

  alias DukaApp.DataDir
  alias DukaApp.Requests.Attachment

  @dir "request_attachments"

  # Enough for a phone photo or a multi-page scanned invoice.
  @max_size 10 * 1024 * 1024
  @max_count 5

  @spec max_count() :: pos_integer()
  def max_count, do: @max_count

  @doc """
  Copies the file at `source` in and returns an unsaved attachment for it.
  `name` is what to show the user; `content_type` must be an image or a PDF.
  """
  @spec store(String.t(), String.t(), String.t()) ::
          {:ok, Attachment.t()} | {:error, :unsupported | :too_large | File.posix()}
  def store(source, name, content_type) do
    with :ok <- check_type(content_type),
         {:ok, %File.Stat{size: size}} <- File.stat(source),
         :ok <- check_size(size) do
      file_name =
        "attachment-#{System.os_time(:millisecond)}-#{:rand.uniform(1_000_000)}" <>
          extension(name, content_type)

      with :ok <- File.cp(source, path(file_name)) do
        {:ok,
         %Attachment{file_name: file_name, name: name, content_type: content_type, size: size}}
      end
    end
  end

  @doc "Full path of a stored attachment."
  @spec path(String.t()) :: String.t()
  def path(file_name), do: Path.join(DataDir.path(@dir), Path.basename(file_name))

  @doc "Deletes stored attachment files. Missing files are fine."
  @spec delete([Attachment.t()]) :: :ok
  def delete(attachments) do
    Enum.each(attachments, &File.rm(path(&1.file_name)))
  end

  @doc """
  The MIME type for a file the picker or camera didn't label, from its name.

      iex> DukaApp.Requests.Attachments.content_type("Invoice.PDF")
      "application/pdf"

      iex> DukaApp.Requests.Attachments.content_type("notes.txt")
      nil
  """
  @spec content_type(String.t()) :: String.t() | nil
  def content_type(name) do
    case name |> Path.extname() |> String.downcase() do
      ext when ext in [".jpg", ".jpeg"] -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      ".heic" -> "image/heic"
      ".pdf" -> "application/pdf"
      _ -> nil
    end
  end

  @doc """
  A file size for people.

      iex> DukaApp.Requests.Attachments.format_size(2_400_000)
      "2.3 MB"

      iex> DukaApp.Requests.Attachments.format_size(52_000)
      "50 KB"
  """
  @spec format_size(non_neg_integer()) :: String.t()
  def format_size(bytes) when bytes >= 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  def format_size(bytes), do: "#{max(div(bytes, 1024), 1)} KB"

  defp check_type("image/" <> _), do: :ok
  defp check_type("application/pdf"), do: :ok
  defp check_type(_type), do: {:error, :unsupported}

  defp check_size(size) when size > @max_size, do: {:error, :too_large}
  defp check_size(_size), do: :ok

  defp extension(name, content_type) do
    case Path.extname(name) do
      "" -> if content_type == "application/pdf", do: ".pdf", else: ".jpg"
      ext -> String.downcase(ext)
    end
  end
end
