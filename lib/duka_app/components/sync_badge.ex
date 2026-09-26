defmodule DukaApp.Components.SyncBadge do
  @moduledoc """
  Whether a transaction on this phone has reached the team's server:
  a cloud with a tick once it has, a cloud with an arrow while it waits for
  the next sync. A receipt book that isn't connected shows neither, since
  nothing there is ever sent.

  The trailing gap is part of the badge, so it can sit directly in front of
  text.
  """

  import Mob.Sigil

  alias DukaApp.Transactions.Transaction

  @doc """
  True once the server has the transaction as it is now: one edited since
  it was sent isn't synced until it is sent again.
  """
  @spec synced?(Transaction.t()) :: boolean()
  def synced?(%Transaction{remote_id: id, needs_push: needs_push}),
    do: id != nil and not needs_push

  @spec badge(Transaction.t(), boolean()) :: map() | []
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
