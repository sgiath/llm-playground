defmodule Play.UserProfile do
  use Ecto.Schema

  import Ecto.Query

  require Logger

  @behaviour SgiathAuth.Profile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_profiles" do
    field :user_id, :string

    timestamps(type: :utc_datetime)
  end

  def fetch_by_id(profile_id) do
    __MODULE__
    |> where(id: ^profile_id)
    |> Play.Repo.one()
  end

  def fetch_by_user_id(user_id) do
    __MODULE__
    |> where(user_id: ^user_id)
    |> Play.Repo.all()
  end

  def create!(%{"id" => user_id} = _user) do
    %__MODULE__{}
    |> Ecto.Changeset.change(user_id: user_id)
    |> Play.Repo.insert!()
  end

  @impl SgiathAuth.Profile
  def load_profile(%{"id" => user_id} = user) do
    case fetch_by_user_id(user_id) do
      [] ->
        create!(user)

      [profile] ->
        profile

      profiles when is_list(profiles) ->
        Logger.error("Multiple user profiles found for user #{user_id}")
        nil
    end
  end
end
