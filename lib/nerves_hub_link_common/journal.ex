defmodule NervesHubLinkCommon.Journal do
  @moduledoc """
  Simple journaling structure backed by a file on the filesystem

  Stores data in chunks in the following format:

    <<length::32, hash::binary-size(32)-unit(8), data::binary-size(length)-unit(8)>>

  as chunks are streamed with `save_chunk/2` the data is updated both on disk and
  in the structure. This can be used to rehydrate stateful events after a reboot, such as
  a firmware update for example.

  When opening an existing journal (done automatically if the journal exists),
  the structure will validate all the chunks on disk, stopping on either

    * the first chunk to fail a hash check
    * the end of the file

  In either case, the journal is valid to use at this point
  """

  defstruct [:fd, :content_length, :chunks]

  @type t :: %__MODULE__{
          fd: :file.fd(),
          content_length: non_neg_integer(),
          chunks: [binary()]
        }

  @doc "Open or create a journal for this meta"
  @spec open(Path.t()) :: {:ok, t()} | {:error, File.posix()}
  def open(filename) do
    with {:ok, fd} <- :file.open(filename, [:write, :read, :binary]),
         {:ok, 0} <- :file.position(fd, 0),
         {:ok, journal} <- validate_and_seek(%__MODULE__{fd: fd, content_length: 0, chunks: []}) do
      {:ok, journal}
    end
  end

  @spec reload(Path.t()) :: {:ok, t()} | {:error, File.posix()}
  def reload(filename) do
    if File.exists?(filename) do
      open(filename)
    else
      {:error, :enoent}
    end
  end

  @spec validate_and_seek(t()) :: {:ok, t()} | {:error, File.posix()}
  def validate_and_seek(%__MODULE__{fd: fd, content_length: content_length} = journal) do
    with {:ok, <<length::32>>} <- :file.read(fd, 4),
         {:ok, hash} <- :file.read(fd, 32),
         {:ok, data} <- :file.read(fd, length),
         {:hash, ^length, ^hash} <- {:hash, length, :crypto.hash(:sha256, data)} do
      validate_and_seek(%__MODULE__{
        journal
        | content_length: content_length + length,
          chunks: journal.chunks ++ [data]
      })
    else
      # made it thru all chunks in the file
      :eof ->
        {:ok, journal}

      # hash check failed. rewind and break
      {:hash, length, _} ->
        rewind(journal, length + 32 + 4)

      {:error, posix} ->
        {:error, posix}
    end
  end

  @spec rewind(t(), pos_integer()) :: {:ok, t()} | {:error, File.posix()}
  def rewind(journal, length) do
    with {:ok, _} <- :file.position(journal.fd, -length) do
      {:ok, journal}
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{fd: fd} = _journal) do
    :ok = :file.close(fd)
  end

  @spec save_chunk(t(), iodata()) :: {:ok, t()} | {:error, File.posix()}
  def save_chunk(%__MODULE__{fd: fd} = journal, data) when is_binary(data) do
    hash = :crypto.hash(:sha256, data)
    length = byte_size(data)
    journal_entry = IO.iodata_to_binary([<<length::32>>, hash, data])

    with :ok <- :file.write(fd, journal_entry) do
      {:ok,
       %__MODULE__{
         journal
         | chunks: journal.chunks ++ [data],
           content_length: journal.content_length + length
       }}
    end
  end
end
