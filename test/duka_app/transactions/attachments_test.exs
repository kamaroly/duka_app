defmodule DukaApp.Transactions.AttachmentsTest do
  use ExUnit.Case, async: true

  alias DukaApp.Transactions.{Attachment, Attachments}

  doctest Attachments

  @moduletag :tmp_dir

  test "copies an image or PDF in, keeping its name, type and size", %{tmp_dir: dir} do
    source = Path.join(dir, "mob_file_123_invoice.pdf")
    File.write!(source, "%PDF-1.4 hello")

    assert {:ok, %Attachment{} = attachment} =
             Attachments.store(source, "Invoice 104.pdf", "application/pdf")

    assert %{name: "Invoice 104.pdf", content_type: "application/pdf", size: 14} = attachment
    assert String.ends_with?(attachment.file_name, ".pdf")
    assert File.read!(Attachments.path(attachment.file_name)) == "%PDF-1.4 hello"

    # The copy outlives the picker's temp file, and delete removes it.
    File.rm!(source)
    assert File.exists?(Attachments.path(attachment.file_name))
    Attachments.delete([attachment])
    refute File.exists?(Attachments.path(attachment.file_name))
  end

  test "refuses other types and files over 10 MB", %{tmp_dir: dir} do
    text = Path.join(dir, "notes.txt")
    File.write!(text, "hi")
    assert Attachments.store(text, "notes.txt", "text/plain") == {:error, :unsupported}

    big = Path.join(dir, "big.jpg")
    File.write!(big, :binary.copy("x", 10 * 1024 * 1024 + 1))
    assert Attachments.store(big, "big.jpg", "image/jpeg") == {:error, :too_large}
  end
end
