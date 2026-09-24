# mob_nif.so only exists on a phone. On the host the code loader logs a
# "The on_load function for module mob_nif returned ... load_failed" warning
# the first time a test touches Mob's native layer; Mob falls back to host
# behaviour, so it is expected noise. Drop exactly that report, nothing else.
:logger.add_primary_filter(
  :mob_nif_host_load,
  {fn
     %{msg: {:report, %{args: [:mob_nif | _]}}}, _ -> :stop
     _event, _ -> :ignore
   end, nil}
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(DukaApp.Repo, :manual)
