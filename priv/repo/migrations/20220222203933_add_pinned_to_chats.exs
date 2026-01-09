defmodule Pleroma.Repo.Migrations.AddPinnedToChats do
  use Ecto.Migration

  def change do
    alter table(:chats) do
      add(:pinned, :boolean, default: false, null: false)
    end

    create(index(:chats, [:pinned]))
  end
end
