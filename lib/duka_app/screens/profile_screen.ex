defmodule DukaApp.Screens.ProfileScreen do
  use Mob.Screen

  import Ecto.Query, only: [from: 2]

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = get_profile()

    {:ok,
     socket
     |> Mob.Socket.assign(:profile, profile)
     |> Mob.Socket.assign(:phone, profile.phone)
     |> Mob.Socket.assign(:email, profile.email)}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column fill_height={true} background={:white} padding={4}>
      <Button text="Back" fill_width={true} padding={:xs} text_size={:sm} on_tap={{self(), :back}} />
      <Scroll padding={:space_lg} background={:white}>
        <Column gap={4} fill_width={true}>
          <Text text="Email" text_size={:sm} text_color={:muted} />
          <TextField
            label="Email"
            value={@email}
            variant={:outlined}
            padding={:space_xs}
            corner_radius={:radius_xs}
            keyboard_type={:email}
            on_change={{self(), :email}}
          />
        </Column>
        <Spacer size={8} />
        <Column gap={4} fill_width={true}>
          <Text text="Phone" text_size={:sm} text_color={:muted} />
          <TextField
            label="Phone Numebr"
            value={@phone}
            variant={:outlined}
            padding={:space_xs}
            corner_radius={:radius_xs}
            keyboard_type={:phone}
            on_change={{self(), :phone}}
          />
        </Column>
        <Spacer size={8} />
        <Text text="Angel is programming" text_size={:xl} text_color={ 0xFF008080} />
        <TextField
          value={""}
          placeholder={""}
          keyboard={:number}
          fill_width={true}
          background={:surface}
          corner_radius={:radius_sm}
          padding={:space_sm}
          border_color={:border}
          border_width={1}
        />
        <Spacer size={8} />
        <Button
          text="Save changes"
          full_width={true}
          padding={:xs}
          margin={16}
          on_tap={{self(), :save}}
        />
      </Scroll>
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  # def handle_info({:change, :email, value}, socket) do
  #   {:noreply, Mob.Socket.assign(socket, :email, value)}
  # end

  # def handle_info({:change, :phone, value}, socket) do
  #   {:noreply, Mob.Socket.assign(socket, :phone, value)}
  # end

  def handle_info({:change, key, value}, socket) do
    {:noreply, Mob.Socket.assign(socket, key, value)}
  end

  def handle_info({:tap, :save}, socket) do
    %{profile: profile} = socket.assigns
    attrs = %{email: socket.assigns.email, phone: socket.assigns.phone}

    case save_profile(profile, attrs) do
      {:ok, saved_profile} ->
        Mob.Alert.toast(socket, "Profile saved")

        socket =
          socket
          |> Mob.Socket.assign(:profile, saved_profile)
          |> Mob.Socket.assign(:phone, saved_profile.phone)
          |> Mob.Socket.assign(:email, saved_profile.email)

        {:noreply, socket}

      {:error, _changeset} ->
        Mob.Alert.toast(socket, "Could not save profile")
        {:noreply, socket}
    end

    {:noreply, Mob.Socket.assign(socket, :profile, get_profile())}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp save_profile(%{id: nil} = _profile, attrs) do
    DukaApp.Repo.insert(%DukaApp.Profile{email: attrs.email, phone: attrs.phone})
  end

  defp save_profile(profile, attrs) do
    profile
    |> DukaApp.Profile.changeset(%{email: attrs.email, phone: attrs.phone})
    |> DukaApp.Repo.update()
  end

  defp get_profile do
    DukaApp.Repo.one(from(p in DukaApp.Profile, limit: 1)) || %DukaApp.Profile{}
  end
end
