defmodule DukaApp.Receipts do
  @moduledoc """
  The receipt book. Every query is scoped to a profile, and everything is
  stored in the on-device SQLite database — no network needed.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.{Photos, QrParser, Receipt}
  alias DukaApp.Repo

  # Nairobi is UTC+3 all year (no daylight saving), so "today" can be computed
  # without a timezone database, which the device runtime does not ship.
  @nairobi_offset 3 * 60 * 60

  # The spend card and the filter chips group the categories three ways.
  @groups [
    food: ["Food & Groceries", "Meals & Entertainment"],
    fuel: ["Fuel", "Transport"]
  ]

  @type group :: :food | :fuel | :other

  defdelegate categories, to: Receipt

  @spec groups() :: [group()]
  def groups, do: [:food, :fuel, :other]

  @doc """
  The spending group a category belongs to.

      iex> DukaApp.Receipts.group("Transport")
      :fuel

      iex> DukaApp.Receipts.group("Rent")
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
  Receipts for `profile`, newest first, optionally filtered by `search`
  (vendor, description, category, or any text read off the photo) and by
  spending group.
  """
  @spec list_receipts(Profile.t(), String.t(), group() | :all) :: [Receipt.t()]
  def list_receipts(%Profile{id: profile_id}, search \\ "", group \\ :all) do
    query =
      from(r in Receipt,
        where: r.profile_id == ^profile_id,
        order_by: [desc: r.date, desc: r.id]
      )
      |> in_group(group)

    case String.trim(search) do
      "" ->
        Repo.all(query)

      term ->
        pattern = "%" <> escape_like(String.downcase(term)) <> "%"

        Repo.all(
          from r in query,
            where:
              fragment("lower(?) LIKE ? ESCAPE '\\'", r.vendor, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", r.description, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", r.category, ^pattern) or
                fragment("lower(?) LIKE ? ESCAPE '\\'", r.ocr_text, ^pattern)
        )
    end
  end

  defp in_group(query, :all), do: query

  defp in_group(query, :other) do
    grouped = Enum.flat_map(@groups, &elem(&1, 1))
    from r in query, where: r.category not in ^grouped
  end

  defp in_group(query, group) do
    categories = Keyword.fetch!(@groups, group)
    from r in query, where: r.category in ^categories
  end

  @spec get_receipt!(Profile.t(), integer()) :: Receipt.t()
  def get_receipt!(%Profile{id: profile_id}, id) do
    Repo.get_by!(Receipt, id: id, profile_id: profile_id)
  end

  @doc "The receipt already saved from this exact QR code, if any."
  @spec find_by_qr(Profile.t(), String.t()) :: Receipt.t() | nil
  def find_by_qr(%Profile{id: profile_id}, qr_content) do
    Repo.get_by(Receipt, profile_id: profile_id, qr_content: String.trim(qr_content))
  end

  @doc """
  An unsaved receipt pre-filled from a scanned QR code, ready for the user to
  confirm. Fields the code does not carry fall back to sensible defaults.
  """
  @spec new_from_qr(String.t()) :: Receipt.t()
  def new_from_qr(qr_content) do
    parsed = QrParser.parse(qr_content)

    new_manual()
    |> put_qr(qr_content)
    |> Map.merge(%{date: parsed.date || today(), amount_cents: parsed.amount_cents})
  end

  @doc """
  Attaches a QR code to a receipt: the raw content plus what the code
  identifies (seller PIN, branch, receipt number, verification link). Used
  both for a QR-first scan and for a QR found in, or added to, a photo.
  """
  @spec put_qr(Receipt.t(), String.t()) :: Receipt.t()
  def put_qr(%Receipt{} = receipt, qr_content) do
    parsed = QrParser.parse(qr_content)

    %{
      receipt
      | qr_content: String.trim(qr_content),
        source: parsed.source,
        seller_pin: parsed.seller_pin || receipt.seller_pin,
        branch_id: parsed.branch_id,
        invoice_number: parsed.invoice_number || receipt.invoice_number,
        verify_url: parsed.verify_url
    }
  end

  @spec new_manual() :: Receipt.t()
  def new_manual, do: %Receipt{source: "manual", date: today(), category: "Other"}

  @spec create_receipt(Profile.t(), Receipt.t(), map()) ::
          {:ok, Receipt.t()} | {:error, Ecto.Changeset.t()}
  def create_receipt(%Profile{id: profile_id}, %Receipt{} = draft, attrs) do
    %{draft | profile_id: profile_id}
    |> Receipt.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_receipt(Receipt.t(), map()) :: {:ok, Receipt.t()} | {:error, Ecto.Changeset.t()}
  def update_receipt(%Receipt{} = receipt, attrs) do
    receipt
    |> Receipt.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes the receipt and its photo."
  @spec delete_receipt(Receipt.t()) :: {:ok, Receipt.t()} | {:error, Ecto.Changeset.t()}
  def delete_receipt(%Receipt{} = receipt) do
    with {:ok, deleted} <- Repo.delete(receipt) do
      Photos.delete(deleted.photo_path)
      {:ok, deleted}
    end
  end

  @doc """
  Receipt count and all-time total, plus the total for `month` (any date in
  it; this month by default) overall and per spending group, in cents.
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

  @doc """
  The first day of each of the last `count` months, newest first.

      iex> DukaApp.Receipts.recent_months(~D[2026-02-14], 3)
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

    from(r in Receipt,
      where: r.profile_id == ^profile_id and r.date >= ^month_start and r.date <= ^month_end,
      group_by: r.category,
      select: {r.category, sum(r.amount_cents)}
    )
    |> Repo.all()
    |> Enum.reduce(empty, fn {category, cents}, acc ->
      Map.update!(acc, group(category), &(&1 + cents))
    end)
  end

  defp totals(profile_id, month_start, month_end) do
    Repo.one(
      from r in Receipt,
        where: r.profile_id == ^profile_id,
        select: %{
          count: count(r.id),
          total: coalesce(sum(r.amount_cents), 0),
          month_total:
            coalesce(
              sum(
                fragment(
                  "CASE WHEN ? BETWEEN ? AND ? THEN ? ELSE 0 END",
                  r.date,
                  ^month_start,
                  ^month_end,
                  r.amount_cents
                )
              ),
              0
            )
        }
    )
  end

  @spec today() :: Date.t()
  def today do
    DateTime.utc_now() |> DateTime.add(@nairobi_offset, :second) |> DateTime.to_date()
  end

  @doc """
  Parses a typed amount into cents.

      iex> DukaApp.Receipts.parse_amount("1,250.5")
      {:ok, 125050}

      iex> DukaApp.Receipts.parse_amount("abc")
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

      iex> DukaApp.Receipts.format_amount(123_450)
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

      iex> DukaApp.Receipts.format_short(120_500)
      "Ksh 1,205"

      iex> DukaApp.Receipts.format_short(120_550)
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
