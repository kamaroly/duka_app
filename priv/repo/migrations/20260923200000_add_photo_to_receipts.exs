defmodule DukaApp.Repo.Migrations.AddPhotoToReceipts do
  use Ecto.Migration

  def change do
    alter table(:receipts) do
      # File name only; DukaApp.Receipts.Photos resolves it against the
      # app's data directory, which can move between installs.
      add :photo_path, :string
      # Everything OCR read off the photo, kept for search and for
      # re-checking the extracted fields.
      add :ocr_text, :text
    end
  end
end
