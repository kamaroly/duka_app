defmodule DukaApp.Transactions do
  @moduledoc """
  The expense book: every expense, refund and payment request (see
  `DukaApp.Transactions.Transaction`). Every query is scoped to a profile,
  and everything is stored in the on-device SQLite database — no network
  needed. A connected book also syncs with the team's server (see
  `DukaApp.Sync`).
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.{Photos, QrParser}
  alias DukaApp.{Repo, Sync}
  alias DukaApp.Transactions.{Attachment, Attachments, Transaction}

  # Nairobi is UTC+3 all year (no daylight saving), so "today" can be computed
  # without a timezone database, which the device runtime does not ship.
  @nairobi_offset 3 * 60 * 60

  # The spend card and the filter chips group the categories three ways.
  @groups [
    food: ["Food & Groceries", "Meals & Entertainment"],
    fuel: ["Fuel", "Transport"]
  ]

  @claims ["refund", "payment_request"]

  @type group :: :food | :fuel | :other
  @type filter :: group() | :all | :claims

  defdelegate categories, to: Transaction

  @spec groups() :: [group()]
  def groups, do: [:food, :fuel, :other]

  @doc """
  The spending group a category belongs to.

      iex> DukaApp.Transactions.group("Transport")
      :fuel

      iex> DukaApp.Transactions.group("Rent")
      :other
  """
  @spec group(String.t() | nil) :: group()
  def group(category) do
    Enum.find_value(@groups, :other, fn {group, categories} ->
      if category in categories, do: group
    end)
  end

  @spec group_label(group()) :: String.t()
  def group_label(:food), do: "Food"
  def group_label(:fuel), do: "Fuel"
  def group_label(:other), do: "Other"

  @doc """
  Transactions for `profile`, newest first, with their attachments,
  optionally filtered by `search` (vendor, description, category, or any
  text read off the photo) and by spending group or to claims (refunds and
  payment requests).
  """
  @spec list_transactions(Profile.t(), String.t(), filter()) :: [Transaction.t()]
  def list_transactions(%Profile{id: profile_id}, search \\ "", filter \\ :all) do
    query =
      from(t in Transaction,
        where: t.profile_id == ^profile_id,
        order_by: [desc: t.date, desc: t.id],
        preload: :attachments
      )
      |> filtered(filter)

    case String.trim(search) do
      "" ->
        Repo.all(query)

      term ->
        pattern = "%" <> escape_like(String.downcase(term)) <> "%"

        Repo.all(
          from t in query,
            where:
              fragment("lower(?) LIKE ? ESCAPE '\\'", t.vendor, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", t.description, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", t.category, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", t.ocr_text, ^pattern)
        )
    end
  end

  defp filtered(query, :all), do: query
  defp filtered(query, :claims), do: from(t in query, where: t.type in ^@claims)

  defp filtered(query, :other) do
    grouped = Enum.flat_map(@groups, &elem(&1, 1))
    from t in query, where: t.category not in ^grouped
  end

  defp filtered(query, group) do
    categories = Keyword.fetch!(@groups, group)
    from t in query, where: t.category in ^categories
  end

  @doc "The transaction, with its attachments, or nil if it no longer exists."
  @spec get_transaction(Profile.t(), integer()) :: Transaction.t() | nil
  def get_transaction(%Profile{id: profile_id}, id) do
    Transaction
    |> Repo.get_by(id: id, profile_id: profile_id)
    |> Repo.preload(:attachments)
  end

  @spec get_transaction!(Profile.t(), integer()) :: Transaction.t()
  def get_transaction!(%Profile{id: profile_id}, id) do
    Transaction
    |> Repo.get_by!(id: id, profile_id: profile_id)
    |> Repo.preload(:attachments)
  end

  @doc "The transaction already saved from this exact QR code, if any."
  @spec find_by_qr(Profile.t(), String.t()) :: Transaction.t() | nil
  def find_by_qr(%Profile{id: profile_id}, qr_content) do
    Transaction
    |> Repo.get_by(profile_id: profile_id, qr_content: String.trim(qr_content))
    |> Repo.preload(:attachments)
  end

  # ── Receipts: QR codes and KRA ──────────────────────────────────────────────

  @doc """
  An unsaved expense pre-filled from a scanned QR code, ready for the user to
  confirm. Fields the code does not carry fall back to sensible defaults.
  """
  @spec new_from_qr(String.t()) :: Transaction.t()
  def new_from_qr(qr_content) do
    parsed = QrParser.parse(qr_content)

    new_expense()
    |> put_qr(qr_content)
    |> Map.merge(%{date: parsed.date || today(), amount_cents: parsed.amount_cents})
  end

  @doc """
  Attaches a QR code to a transaction: the raw content plus what the code
  identifies (seller PIN, branch, receipt number, verification link). Used
  both for a QR-first scan and for a QR found in, or added to, a photo.
  """
  @spec put_qr(Transaction.t(), String.t()) :: Transaction.t()
  def put_qr(%Transaction{} = transaction, qr_content) do
    parsed = QrParser.parse(qr_content)

    %{
      transaction
      | qr_content: String.trim(qr_content),
        source: parsed.source,
        seller_pin: parsed.seller_pin || transaction.seller_pin,
        branch_id: parsed.branch_id,
        invoice_number: parsed.invoice_number || transaction.invoice_number,
        verify_url: parsed.verify_url
    }
  end

  @doc "True for a receipt whose QR code is a KRA (eTIMS, TIMS or other KRA) link."
  @spec kra?(Transaction.t()) :: boolean()
  def kra?(%Transaction{source: source}), do: source in ["etims", "tims", "kra"]

  @doc """
  True when KRA's page for this receipt can be read to verify it: only eTIMS
  and TIMS links lead to a page with the receipt on it.
  """
  @spec verifiable?(Transaction.t()) :: boolean()
  def verifiable?(%Transaction{source: source, verify_url: url}),
    do: source in ["etims", "tims"] and is_binary(url)

  @spec verified?(Transaction.t()) :: boolean()
  def verified?(%Transaction{verified_at: verified_at}), do: not is_nil(verified_at)

  @doc """
  The newest receipt that could be verified with KRA but hasn't been,
  skipping the ids in `except` (ones already tried).
  """
  @spec next_unverified(Profile.t(), Enumerable.t()) :: Transaction.t() | nil
  def next_unverified(%Profile{id: profile_id}, except \\ []) do
    except = Enum.to_list(except)

    Repo.one(
      from t in Transaction,
        where:
          t.profile_id == ^profile_id and is_nil(t.verified_at) and
            t.source in ["etims", "tims"] and not is_nil(t.verify_url) and t.id not in ^except,
        order_by: [desc: t.date, desc: t.id],
        limit: 1
    )
  end

  @doc "Records that KRA's verification page returned this receipt."
  @spec mark_verified(Transaction.t()) :: {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def mark_verified(%Transaction{} = transaction) do
    transaction
    |> Ecto.Changeset.change(verified_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Ecto.Changeset.put_change(:needs_push, true)
    |> Repo.update()
  end

  # ── Adding and changing ────────────────────────────────────────────────────

  @spec new_expense() :: Transaction.t()
  def new_expense,
    do: %Transaction{type: "expense", source: "manual", date: today(), category: "Other"}

  @doc "A draft payment request: paid by M-Pesa send money unless the user changes it."
  @spec new_payment() :: Transaction.t()
  def new_payment,
    do: %Transaction{
      type: "payment_request",
      pay_to: "supplier",
      source: "manual",
      date: today(),
      category: "Other",
      method: "send_money",
      attachments: []
    }

  @doc """
  Saves a new transaction, with the `attachments` already stored by
  `DukaApp.Transactions.Attachments.store/3`, in one database transaction.
  """
  @spec create_transaction(Profile.t(), Transaction.t(), map(), [Attachment.t()]) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def create_transaction(
        %Profile{id: profile_id},
        %Transaction{} = draft,
        attrs,
        attachments \\ []
      ) do
    changeset =
      %{draft | profile_id: profile_id, client_id: draft.client_id || Ecto.UUID.generate()}
      |> Map.put(:attachments, [])
      |> Transaction.changeset(attrs)

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, transaction} ->
          Enum.each(attachments, &Repo.insert!(%{&1 | transaction_id: transaction.id}))
          Repo.preload(transaction, :attachments, force: true)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a transaction. Changing a decided one's figures sends it back for
  approval; a paid one can't be changed.
  """
  @spec update_transaction(Transaction.t(), map()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | :paid}
  def update_transaction(%Transaction{status: "paid"}, _attrs), do: {:error, :paid}

  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> reopen_if_changed()
    |> mark_for_push()
    |> Repo.update()
  end

  @doc """
  Updates a transaction and adds `attachments` (already stored by
  `Attachments.store/3`), in one database transaction. New attachments are
  news for the server even when nothing else changed.
  """
  @spec update_transaction(Transaction.t(), map(), [Attachment.t()]) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | :paid}
  def update_transaction(transaction, attrs, []), do: update_transaction(transaction, attrs)
  def update_transaction(%Transaction{status: "paid"}, _attrs, _attachments), do: {:error, :paid}

  def update_transaction(%Transaction{} = transaction, attrs, attachments) do
    Repo.transaction(fn ->
      changeset =
        transaction
        |> Transaction.changeset(attrs)
        |> reopen_if_changed()
        |> Ecto.Changeset.force_change(:needs_push, true)

      case Repo.update(changeset) do
        {:ok, updated} ->
          Enum.each(attachments, &Repo.insert!(%{&1 | transaction_id: updated.id}))
          Repo.preload(updated, :attachments, force: true)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Asks for an expense back: it becomes a refund, paid as `attrs` say (by
  default M-Pesa to the person's own number), and waits for approval again.
  """
  @spec request_refund(Transaction.t(), map()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | :paid | :not_expense}
  def request_refund(%Transaction{type: "expense"} = transaction, attrs),
    do: update_transaction(transaction, Map.put(attrs, :type, "refund"))

  def request_refund(%Transaction{}, _attrs), do: {:error, :not_expense}

  @doc "A refund still waiting for a decision can be taken back: it becomes an expense again."
  @spec cancel_refund(Transaction.t()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | :not_pending}
  def cancel_refund(%Transaction{type: "refund", status: "pending"} = transaction) do
    update_transaction(transaction, %{
      type: "expense",
      method: nil,
      phone: nil,
      till_number: nil,
      paybill_number: nil,
      account_number: nil
    })
  end

  def cancel_refund(%Transaction{}), do: {:error, :not_pending}

  # Any real change is news for the server; a new photo must be sent again.
  defp mark_for_push(%Ecto.Changeset{changes: changes} = changeset) when changes == %{},
    do: changeset

  defp mark_for_push(changeset) do
    changeset
    |> Ecto.Changeset.put_change(:needs_push, true)
    |> then(fn cs ->
      if Map.has_key?(cs.changes, :photo_path),
        do: Ecto.Changeset.put_change(cs, :photo_pushed, false),
        else: cs
    end)
  end

  # A decided transaction whose figures change goes back to the approver:
  # an approval must be for what they actually saw.
  @decided_fields [
    :type,
    :pay_to,
    :date,
    :vendor,
    :description,
    :amount_cents,
    :category,
    :method,
    :phone,
    :till_number,
    :paybill_number,
    :account_number
  ]

  defp reopen_if_changed(%Ecto.Changeset{data: %{status: "pending"}} = changeset),
    do: changeset

  defp reopen_if_changed(changeset) do
    if Enum.any?(@decided_fields, &Map.has_key?(changeset.changes, &1)),
      do:
        Ecto.Changeset.change(changeset,
          status: "pending",
          decision_note: nil,
          decided_at: nil
        ),
      else: changeset
  end

  @doc """
  Deletes the transaction, its photo and attachments. In a connected book the
  next sync deletes it on the server too, so only one still waiting for a
  decision can go.
  """
  @spec delete_transaction(Transaction.t()) :: {:ok, Transaction.t()} | {:error, :decided}
  def delete_transaction(%Transaction{} = transaction) do
    connected? = Profile.connected?(Repo.get(Profile, transaction.profile_id))

    if connected? and transaction.status != "pending",
      do: {:error, :decided},
      else: delete_and_remember(transaction, connected?)
  end

  defp delete_and_remember(transaction, connected?) do
    attachments = transaction |> Repo.preload(:attachments) |> Map.fetch!(:attachments)

    {:ok, deleted} =
      Repo.transaction(fn ->
        deleted = Repo.delete!(transaction)
        if connected?, do: Sync.remember_deletion(deleted.profile_id, deleted.client_id)
        deleted
      end)

    Photos.delete(deleted.photo_path)
    Attachments.delete(attachments)
    {:ok, deleted}
  end

  @doc """
  Records a decision: `"approved"` or `"rejected"` (with an optional note),
  or `"paid"` once an approved claim has been paid.
  """
  @spec decide(Transaction.t(), String.t(), String.t() | nil) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def decide(%Transaction{} = transaction, status, note \\ nil) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    transaction
    |> Transaction.decision_changeset(%{
      status: status,
      decision_note: note,
      decided_at: now,
      paid_at: if(status == "paid", do: now)
    })
    |> Repo.update()
  end

  # ── Totals ─────────────────────────────────────────────────────────────────

  @doc """
  Count and all-time total, plus the total for `month` (any date in it; this
  month by default) overall and per spending group, in cents. Rejected
  transactions don't count as spend.
  """
  @spec summary(Profile.t(), Date.t()) :: %{
          count: integer(),
          total: integer(),
          month_total: integer(),
          month_by_group: %{group() => integer()}
        }
  def summary(%Profile{id: profile_id} = profile, month \\ today()) do
    month_start = Date.beginning_of_month(month)
    month_end = Date.end_of_month(month)

    profile_id
    |> totals(month_start, month_end)
    |> Map.put(:month_by_group, month_by_group(profile, month_start, month_end))
  end

  @doc "Refunds and payment requests waiting for a decision, and their total, in cents."
  @spec pending_claims(Profile.t()) :: %{count: integer(), total: integer()}
  def pending_claims(%Profile{id: profile_id}) do
    Repo.one(
      from t in Transaction,
        where: t.profile_id == ^profile_id and t.status == "pending" and t.type in ^@claims,
        select: %{count: count(t.id), total: coalesce(sum(t.amount_cents), 0)}
    )
  end

  @doc """
  The first day of each of the last `count` months, newest first.

      iex> DukaApp.Transactions.recent_months(~D[2026-02-14], 3)
      [~D[2026-02-01], ~D[2026-01-01], ~D[2025-12-01]]
  """
  @spec recent_months(Date.t(), pos_integer()) :: [Date.t()]
  def recent_months(today \\ today(), count) do
    today
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.beginning_of_month(Date.add(&1, -1)))
    |> Enum.take(count)
  end

  defp month_by_group(%Profile{id: profile_id}, month_start, month_end) do
    empty = Map.new(groups(), &{&1, 0})

    from(t in Transaction,
      where:
        t.profile_id == ^profile_id and t.status != "rejected" and t.date >= ^month_start and
          t.date <= ^month_end,
      group_by: t.category,
      select: {t.category, sum(t.amount_cents)}
    )
    |> Repo.all()
    |> Enum.reduce(empty, fn {category, cents}, acc ->
      Map.update!(acc, group(category), &(&1 + cents))
    end)
  end

  defp totals(profile_id, month_start, month_end) do
    Repo.one(
      from t in Transaction,
        where: t.profile_id == ^profile_id and t.status != "rejected",
        select: %{
          count: count(t.id),
          total: coalesce(sum(t.amount_cents), 0),
          month_total:
            coalesce(
              sum(
                fragment(
                  "CASE WHEN ? BETWEEN ? AND ? THEN ? ELSE 0 END",
                  t.date,
                  ^month_start,
                  ^month_end,
                  t.amount_cents
                )
              ),
              0
            )
        }
    )
  end

  # ── Labels and formats ─────────────────────────────────────────────────────

  @spec type_label(String.t()) :: String.t()
  def type_label("expense"), do: "Expense"
  def type_label("refund"), do: "Refund"
  def type_label("payment_request"), do: "Payment request"

  @spec status_label(String.t()) :: String.t()
  def status_label("pending"), do: "Pending approval"
  def status_label("approved"), do: "Approved"
  def status_label("rejected"), do: "Rejected"
  def status_label("paid"), do: "Paid"

  @spec method_label(String.t() | nil) :: String.t() | nil
  def method_label("cash"), do: "Cash"
  def method_label("send_money"), do: "Send money"
  def method_label("till"), do: "Till (Buy Goods)"
  def method_label("paybill"), do: "Paybill"
  def method_label("card"), do: "Card"
  def method_label("bank"), do: "Bank transfer"
  def method_label("other"), do: "Other"
  def method_label(nil), do: nil

  @doc """
  Where the money goes, in one line; nil when no way of paying is set.

      iex> DukaApp.Transactions.pay_details(%DukaApp.Transactions.Transaction{method: "paybill", paybill_number: "400200", account_number: "12345"})
      "Paybill 400200 · Acc 12345"

      iex> DukaApp.Transactions.pay_details(%DukaApp.Transactions.Transaction{method: "send_money", phone: "+254712345678"})
      "M-Pesa 0712 345 678"
  """
  @spec pay_details(Transaction.t()) :: String.t() | nil
  def pay_details(%Transaction{method: "send_money", phone: phone}),
    do: "M-Pesa #{local_phone(phone)}"

  def pay_details(%Transaction{method: "till", till_number: till}), do: "Till #{till}"

  def pay_details(%Transaction{method: "paybill", paybill_number: paybill, account_number: acc}),
    do: "Paybill #{paybill} · Acc #{acc}"

  def pay_details(%Transaction{method: method}), do: method_label(method)

  @doc """
  A `+254…` number as it's usually written in Kenya.

      iex> DukaApp.Transactions.local_phone("+254712345678")
      "0712 345 678"
  """
  @spec local_phone(String.t() | nil) :: String.t()
  def local_phone("+254" <> <<a::binary-size(3), b::binary-size(3), c::binary-size(3)>>),
    do: "0#{a} #{b} #{c}"

  def local_phone(phone), do: phone || ""

  @spec today() :: Date.t()
  def today do
    DateTime.utc_now() |> DateTime.add(@nairobi_offset, :second) |> DateTime.to_date()
  end

  @doc """
  Parses a typed amount into cents.

      iex> DukaApp.Transactions.parse_amount("1,250.5")
      {:ok, 125050}

      iex> DukaApp.Transactions.parse_amount("abc")
      :error
  """
  @spec parse_amount(String.t() | nil) :: {:ok, non_neg_integer()} | :error
  def parse_amount(nil), do: :error

  def parse_amount(text) when is_binary(text) do
    cleaned = text |> String.replace(~r/ksh\.?|kes|[\s,]/i, "")

    case Regex.run(~r/^(\d+)(?:\.(\d{1,2}))?$/, cleaned) do
      [_, shillings] -> {:ok, String.to_integer(shillings) * 100}
      [_, shillings, cents] -> {:ok, String.to_integer(shillings) * 100 + cents_value(cents)}
      nil -> :error
    end
  end

  defp cents_value(<<d>>), do: (d - ?0) * 10
  defp cents_value(two), do: String.to_integer(two)

  @doc """
  Formats cents for display.

      iex> DukaApp.Transactions.format_amount(123_450)
      "Ksh 1,234.50"
  """
  @spec format_amount(integer() | nil) :: String.t()
  def format_amount(nil), do: "Ksh 0.00"

  def format_amount(cents) when is_integer(cents) do
    shillings =
      div(cents, 100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/.{3}(?=.)/, "\\0,")
      |> String.reverse()

    "Ksh #{shillings}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  @doc """
  Formats cents for a compact display, dropping the cents when there are none.

      iex> DukaApp.Transactions.format_short(120_500)
      "Ksh 1,205"

      iex> DukaApp.Transactions.format_short(120_550)
      "Ksh 1,205.50"
  """
  @spec format_short(integer() | nil) :: String.t()
  def format_short(cents) do
    amount = format_amount(cents)
    if String.ends_with?(amount, ".00"), do: String.slice(amount, 0..-4//1), else: amount
  end

  @doc "Cents as a plain editable number, e.g. `\"1234.50\"`."
  @spec amount_input(integer() | nil) :: String.t()
  def amount_input(nil), do: ""

  def amount_input(cents) do
    "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp escape_like(term), do: String.replace(term, ~r/([\\%_])/, "\\\\\\1")
end
