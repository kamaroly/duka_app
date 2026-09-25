defmodule DukaApp.Components.SyncBadge do
  @moduledoc """
  Whether a receipt or request on this phone has reached the team's server:
  a cloud with a tick once it has, a cloud with an arrow while it waits for
  the next sync. A receipt book that isn't connected shows neither, since
  nothing there is ever sent.

  The trailing gap is part of the badge, so it can sit directly in front of
  text.
  """

  import Mob.Sigil

  alias DukaApp.Receipts.Receipt
  alias DukaApp.Requests.Request

  @doc """
  True once the server has the record as it is now: a receipt edited since
  it was sent isn't synced until it is sent again.
  """
  @spec synced?(Receipt.t() | Request.t()) :: boolean()
  def synced?(%Receipt{remote_id: id, needs_push: needs_push}), do: id != nil and not needs_push
  def synced?(%Request{remote_id: id}), do: id != nil

  @spec badge(Receipt.t() | Request.t(), boolean()) :: map() | []
  def badge(_record, false = _connected), do: []

  def badge(record, true = _connected) do
    {icon, color, label} =
      if synced?(record),
        do: {"cloud_done", :secondary, "Synced with your team"},
        else: {"cloud_upload", :muted, "Waiting to sync"}

    ~MOB"""
    <Row align={:center} accessibility_label={label}>
      <Icon name={icon} text_size={13} text_color={color} />
      <Spacer size={4} />
    </Row>
    """
  end
end
