[
  # Dialyzer's success typing narrows the opaque %Ecto.Multi{} returned by
  # `Ecto.Multi.new()` to an overly-specific shape (based on the literal
  # empty struct), then flags the very next chained `Ecto.Multi.update/3`
  # call as an opaqueness mismatch. This reproduces on stock, unmodified
  # `mix phx.gen.auth` output (Accounts.reset_user_password/2) — it's a
  # known Dialyzer/Ecto.Multi interaction, not a real type error.
  {"lib/pulsewatch/accounts.ex", :call_without_opaque}
]
