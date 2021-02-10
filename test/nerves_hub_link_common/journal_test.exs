defmodule NervesHubLinkCommon.JournalTest do
  use ExUnit.Case

  alias NervesHubLinkCommon.Journal

  setup do
    {:ok, [path: "/tmp/#{System.unique_integer([:positive])}.journal"]}
  end

  test "journals data to the filesystem", %{path: path} do
    {:ok, journal} = Journal.open(path)
    {:ok, journal1} = Journal.save_chunk(journal, "hello")
    assert journal1.content_length == byte_size("hello")
    assert "hello" in journal1.chunks

    {:ok, journal2} = Journal.save_chunk(journal1, "world")
    :ok = Journal.close(journal2)

    {:ok, journal} = Journal.open(path)
    assert journal.chunks == ["hello", "world"]
  end

  test "stops when journal chunk hashes don't match", %{path: path} do
    hash = :crypto.hash(:sha256, "hello")
    :ok = File.write!(path, [<<5::32>>, hash, "hello"])
    :ok = File.write!(path, [<<5::32>>, <<0::32>>, "world"], [:append])
    {:ok, journal} = Journal.open(path)
    assert journal.content_length == 5
    assert "hello" in journal.chunks
    refute "world" in journal.chunks
  end
end
