# Chapter 17: The Whole Transaction

Previously, we stepped back and looked at the whole system: three types of
transaction, a short status diagram, and one rule that holds it together,
**the phone owns the figures, the server owns the decisions**. That chapter
had no code. This one puts all of it into the phone's database.

Part I's `transactions` table only knows about expenses. Every row is an
`"expense"`, nothing is ever approved, and nothing could be synced, because
nothing has an id the server could recognise. By the end of this chapter the
same table holds refunds and payment requests, every row has a status, and
every row carries the `client_id` that Part IV will hang sync on.

There's no new screen here. The home screen and the form learn about all
this in the next few chapters. This one is about the data, and the rules
that guard it, tested from top to bottom without a phone.

By the end of this chapter, you will know:

- How to grow a table that's already on people's phones, with a migration
  that also fills in the rows that are already there.
- How one schema holds three types, each with its own rules.
- Why the figures and the decisions get two separate changesets.
- Where `client_id` is made, and why nothing can change it afterwards.
- How the context enforces "change the figures, lose the approval" and
  "paid means final".

## One more migration

Remember the rule from Chapter 12: **a migration that has shipped can never
change.** Our `create_transactions` migration is on your phone already, and
in a real release it would be on everyone's. So the new columns come in a
new migration:

```
mix ecto.gen.migration add_claims_and_status_to_transactions
```

```elixir
# priv/repo/migrations/20261006090000_add_claims_and_status_to_transactions.exs
defmodule RisitiApp.Repo.Migrations.AddClaimsAndStatusToTransactions do
  use Ecto.Migration

  def up do
    alter table(:transactions) do
      # Refunds and payment requests: who is paid, and how.
      add :pay_to, :string
      add :method, :string
      add :phone, :string
      add :till_number, :string
      add :paybill_number, :string
      add :account_number, :string

      # pending -> approved | rejected, and for claims approved -> paid.
      add :status, :string, null: false, default: "pending"
      add :decision_note, :string
      add :decided_at, :utc_datetime
      add :paid_at, :utc_datetime

      # The phone's own id for the transaction; sync is keyed on it.
      add :client_id, :string
    end

    flush()

    # Receipts saved before this migration need a client id too. SQLite can
    # make 16 random bytes; written as hex they're as unique as a UUID.
    execute "UPDATE transactions SET client_id = lower(hex(randomblob(16))) WHERE client_id IS NULL"

    create unique_index(:transactions, [:client_id])
  end

  def down do
    drop index(:transactions, [:client_id])

    alter table(:transactions) do
      remove :pay_to
      remove :method
      remove :phone
      remove :till_number
      remove :paybill_number
      remove :account_number
      remove :status
      remove :decision_note
      remove :decided_at
      remove :paid_at
      remove :client_id
    end
  end
end
```

The columns come in three groups, the same three you saw in Chapter 16:
how a claim is paid, where it stands, and the id sync needs. Everything is
nullable except `status`, because an expense has no till number and nothing
undecided has a `decided_at`.

The interesting part is what happens to the rows that are already there.

**Status gets a default.** SQLite fills `"pending"` into every existing row
as the column is added. Every receipt you saved in Part I is now a pending
expense, which is exactly right: nobody has looked at it yet.

**`client_id` can't have a default.** A default is one value for every row,
and the whole point of `client_id` is that no two rows share one. So the
migration adds the column empty, then fills each row with its own random
value in SQL. `randomblob(16)` is 16 random bytes, the same amount of
randomness as a UUID; `hex/1` and `lower/1` turn it into text. It doesn't
have a UUID's dashes, but nothing downstream cares about the shape, only
that it's unique and never changes.

**`flush/0`** runs the `alter table` before the `UPDATE`. Ecto collects a
migration's commands and runs them at the end, so without `flush/0` the
`UPDATE` could reach SQLite before the column exists.

**`up` and `down`, not `change`.** Ecto can work out how to undo
`alter table ... add`, but not how to undo a raw `execute` of SQL. So this
migration says both directions itself. On a phone, `down` never runs: the
app only ever migrates up, at boot. It's there for you, when you roll back a
migration on your computer while you're still getting it right.

Then the unique index, created last, once every row has a value. It's what
lets `client_id` be trusted as a key: SQLite itself refuses a duplicate.

> **How the real Risiti got here.** Not this tidily. The real app first had
> a `receipts` table for expenses and a separate `requests` table for
> payment requests, each with its own migrations. It took a while to see
> that they were the same thing, and a migration on September 28th moved
> both into today's `transactions` table, on phones that already had data
> in them. If you're tempted to give each type its own table, that's the
> road. The book takes the shortcut I wish I'd taken.

## The schema

Now `RisitiApp.Transactions.Transaction` learns the new fields and the
rules that go with them. Replace the top of the module, down to the end of
`changeset/2`:

```elixir
# lib/risiti_app/transactions/transaction.ex
defmodule RisitiApp.Transactions.Transaction do
  @moduledoc """
  One expense, whatever form it takes. Its `type` is:

    * `"expense"` — money already spent: Date | Vendor | Description |
      Amount | Category, and the receipt photo when there is one (see
      `RisitiApp.Receipts.Photos`);
    * `"refund"` — an expense the person paid and wants back, to their own
      M-Pesa number unless they change it;
    * `"payment_request"` — money the person asks the team to pay: to a
      supplier (`pay_to: "supplier"`) or to themselves as an advance.

  Refunds and payment requests are *claims*: once approved they wait to be
  paid. Each way of paying (`method`) needs its own details: a phone for
  M-Pesa send money, a till number for Buy Goods, a paybill and account
  number for a paybill.

  Status runs `pending` → `approved` | `rejected`, and for claims
  `approved` → `paid`. Amounts are whole cents so totals never pick up
  floating-point drift.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @categories [
    "Food & Groceries",
    "Meals & Entertainment",
    "Transport",
    "Fuel",
    "Utilities",
    "Airtime & Internet",
    "Rent",
    "Health",
    "Office Supplies",
    "Other"
  ]

  @types ~w(expense refund payment_request)
  @statuses ~w(pending approved rejected paid)
  @methods ~w(cash send_money till paybill card bank other)
  # "manual" when typed in, "photo" when it came with a receipt photo.
  @sources ~w(manual photo)

  @business_number ~r/^\d{5,7}$/

  schema "transactions" do
    field :type, :string, default: "expense"
    field :pay_to, :string
    field :date, :date
    field :vendor, :string
    field :description, :string
    field :amount_cents, :integer
    field :category, :string

    field :method, :string
    field :phone, :string
    field :till_number, :string
    field :paybill_number, :string
    field :account_number, :string

    field :source, :string, default: "manual"
    field :photo_path, :string

    field :status, :string, default: "pending"
    field :decision_note, :string
    field :decided_at, :utc_datetime
    field :paid_at, :utc_datetime

    field :client_id, :string

    timestamps()
  end

  def categories, do: @categories
  def methods, do: @methods
  def statuses, do: @statuses

  @doc "True for refunds and payment requests, which are paid out once approved."
  def claim?(%{type: type}), do: type in ["refund", "payment_request"]

  @doc "Changeset for what the person enters: the figures and, for a claim, how to pay."
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
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
      :account_number,
      :source,
      :photo_path
    ])
    |> trim([:vendor, :description, :phone, :till_number, :paybill_number, :account_number])
    |> validate_required([:type, :date, :vendor, :amount_cents, :category, :source])
    |> validate_inclusion(:type, @types)
    |> validate_number(:amount_cents, greater_than: 0, message: "must be more than zero")
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:source, @sources)
    |> validate_length(:vendor, max: 120)
    |> validate_length(:description, max: 500)
    |> put_pay_to()
    |> validate_type()
    |> validate_method()
    |> unique_constraint(:client_id)
  end

  @doc "Changeset for a decision (and for marking a claim paid)."
  def decision_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:status, :decision_note, :decided_at, :paid_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:decision_note, max: 300)
  end
```

followed by the private helpers:

```elixir
  # Nobody for an expense (already paid), the person for a refund, and for
  # a payment request a supplier unless it's an advance to themselves.
  defp put_pay_to(changeset) do
    pay_to =
      case get_field(changeset, :type) do
        "expense" -> nil
        "refund" -> "self"
        "payment_request" -> get_field(changeset, :pay_to) || "supplier"
        _ -> get_field(changeset, :pay_to)
      end

    changeset
    |> put_change(:pay_to, pay_to)
    |> validate_inclusion(:pay_to, ~w(self supplier))
  end

  # A claim says how it's to be paid.
  defp validate_type(changeset) do
    if get_field(changeset, :type) in ["refund", "payment_request"],
      do: validate_required(changeset, [:method], message: "choose how to pay"),
      else: changeset
  end

  defp validate_method(changeset) do
    changeset = validate_inclusion(changeset, :method, @methods)

    case get_field(changeset, :method) do
      "send_money" ->
        changeset
        |> validate_required([:phone], message: "enter the phone number to pay")
        |> normalize_phone()

      "till" ->
        changeset
        |> validate_required([:till_number], message: "enter the till number")
        |> validate_format(:till_number, @business_number, message: "is 5 to 7 digits")

      "paybill" ->
        changeset
        |> validate_required([:paybill_number], message: "enter the paybill number")
        |> validate_format(:paybill_number, @business_number, message: "is 5 to 7 digits")
        |> validate_required([:account_number], message: "enter the account number")
        |> validate_length(:account_number, max: 20)

      _ ->
        changeset
    end
  end

  defp normalize_phone(changeset) do
    case get_field(changeset, :phone) do
      nil ->
        changeset

      raw ->
        case RisitiApp.Phone.normalize(raw) do
          {:ok, phone} -> put_change(changeset, :phone, phone)
          :error -> add_error(changeset, :phone, "is not a valid Kenyan mobile number")
        end
    end
  end
```

`trim/2` and `blank_to_nil/1` stay as they were.

Let's break down what we just did.

### The type is cast now

In Chapter 12 I said `type` wasn't cast on purpose: the person entering an
expense shouldn't be able to turn it into a refund by sending
`type: "refund"`. Now we *want* them to, from the screens Chapter 21 builds.
So `type` joins the cast list, and the rules that make a refund a refund
come with it. Turning an expense into a claim isn't a loophole anymore; it's
a feature with its own validation, and, as we'll see in the context, it
sends the transaction to the approver like any other change.

`validate_inclusion(:type, @types)` keeps out anything that isn't one of the
three. If you've used Ecto.Enum, you might wonder why these are plain
strings. It's because they travel. The same values go over JSON to the
server and back, get stored in SQLite and in Postgres, and get compared in
SQL (`t.status != "rejected"`). Plain lowercase strings mean the same thing
everywhere, with no conversion in between.

### Who is paid

`put_pay_to/1` doesn't validate `pay_to` so much as decide it:

- An **expense** pays nobody. The money was spent already, so `pay_to` is
  `nil`, whatever was sent.
- A **refund** always pays the person who spent it: `"self"`.
- A **payment request** pays a `"supplier"` unless the person said `"self"`,
  which makes it an advance.

Deciding it in the changeset means no screen has to remember the rule. A
form that turns an expense into a refund doesn't send `pay_to` at all; the
changeset fills it in.

### How to pay

A claim must say how it's to be paid, and that's `validate_type/1`: refunds
and payment requests require a `method`, with the message "choose how to
pay". An expense doesn't need one.

Then `validate_method/1` asks for whatever that method needs. This is the
part that comes straight from how money moves in Kenya:

| Method | What it needs | Checked how |
|---|---|---|
| `send_money` | The phone number to pay | A Kenyan mobile number, stored as `+2547…` |
| `till` | A Buy Goods till number | 5 to 7 digits |
| `paybill` | A paybill number and an account number | 5 to 7 digits; an account of up to 20 characters |
| `cash`, `card`, `bank`, `other` | Nothing more | |

Note that the details are checked even when they're not required. A cash
claim with a till number of "12" passes, because nobody will use that till
number; a till claim with "12" fails. That's what the `case` on the method
gives us: each method checks only its own fields.

### Phone numbers

People write the same M-Pesa number at least four ways: `0712 345 678`,
`0712345678`, `254712345678`, `+254 712 345 678`. Whoever pays the claim
needs one of them, and comparing two numbers needs them all the same. So the
changeset turns whatever was typed into one form, `+254712345678`, and
refuses anything that isn't a Kenyan mobile number.

That logic gets its own small module, because Part IV needs it again for the
person's own number when they sign in. Create `lib/risiti_app/phone.ex`:

```elixir
# lib/risiti_app/phone.ex
defmodule RisitiApp.Phone do
  @moduledoc """
  Kenyan mobile numbers, the way M-Pesa needs them.

  (In the real Risiti this lives in `RisitiApp.Accounts.Profile`, next to the
  signed-in person's own number. Profiles arrive in Part IV.)
  """

  @doc """
  Turns the ways people write a Safaricom or Airtel number into one form:

      iex> RisitiApp.Phone.normalize("0712 345 678")
      {:ok, "+254712345678"}

      iex> RisitiApp.Phone.normalize("254112345678")
      {:ok, "+254112345678"}

      iex> RisitiApp.Phone.normalize("12345")
      :error
  """
  def normalize(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s\-()]/, "")

    case Regex.run(~r/^(?:\+?254|0)?([17]\d{8})$/, digits) do
      [_, local] -> {:ok, "+254" <> local}
      nil -> :error
    end
  end
end
```

The regular expression reads: an optional `+254`, `254` or `0`, then nine
digits starting with `7` or `1`. Kenyan mobile numbers start with 07 or 01
(the 01 range came when the 07 numbers ran out), and the nine digits after
the prefix are the same however you write the front. We keep those nine and
put `+254` in front of them.

The examples in `@doc` aren't just documentation. In the tests below, one
line, `doctest RisitiApp.Phone`, runs them.

### Two changesets

The last thing to notice is that there are now *two* changesets, and they
cast completely different fields:

- **`changeset/2`** casts the figures: what was spent, where, on what, and
  how to pay it back. It never casts `status`.
- **`decision_changeset/2`** casts the decision: `status`, the note, and
  when it was decided and paid. It never casts the amount.

That's the rule from Chapter 16, written in Ecto. The form screen uses
`changeset/2`, so no amount of tapping on the phone can approve anything.
Decisions come through `decision_changeset/2`, and in Part IV they come only
from the server. If you've wondered why Phoenix generators like to write
`registration_changeset` and `password_changeset` rather than one big
`changeset`, this is the same idea: a changeset is a statement of *who is
allowed to change what*.

Note what `decision_changeset/2` doesn't check: whether the move is allowed.
It would let you mark a rejected expense as paid. On the phone that's fine,
because the phone doesn't decide; it records what the server decided. The
server is where "only an approved claim can be paid" is enforced, by Ash, in
Chapter 26.

## `client_id`

The schema has a `client_id` field, and it isn't in either cast list. That's
deliberate. Nothing a screen sends, and nothing the server sends, can change
it. It's set exactly once, when the transaction is created, by the context.

Open `lib/risiti_app/transactions.ex` and change `create_transaction/1`:

```elixir
  @doc """
  Saves a new transaction. It gets its `client_id` here, once, and keeps it
  for life: sync is keyed on it.
  """
  def create_transaction(attrs) do
    %Transaction{client_id: Ecto.UUID.generate()}
    |> Transaction.changeset(attrs)
    |> Repo.insert()
  end
```

The id goes into the struct *before* the changeset sees the attrs. That's
the difference between data and changes. The changeset starts from a
transaction that already has its `client_id`, and since `client_id` isn't
cast, nothing in `attrs` can replace it.

Why not `autogenerate: true`, or a `@primary_key` of type `:binary_id`?
Because the phone already has a primary key, the integer `id`, and the
screens use it, as they have since Chapter 5. The integer is the phone's
business: it's what SQLite gives each row, and two phones will happily hand
out the same `id: 1`. The `client_id` is the transaction's name for the rest
of the world. Keeping them apart means the `id` can stay small and local,
and the `client_id` can be what the server stores.

`unique_constraint(:client_id)` at the end of `changeset/2` pairs with the
unique index. If a duplicate ever reached SQLite, the insert would come back
as `{:error, changeset}` with an error on `client_id`, instead of raising.
With 122 random bits per UUID, I don't expect to see it. But "can't happen"
and "is handled" are different things, and the second costs one line.

## The context

The context gets the rest of the rules: what may change, and what happens
when it does.

### Changing a decided transaction

Replace `update_transaction/2`:

```elixir
  @doc """
  Updates a transaction. Changing a decided one's figures sends it back for
  approval; a paid one can't be changed.
  """
  def update_transaction(%Transaction{status: "paid"}, _attrs), do: {:error, :paid}

  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> reopen_if_changed()
    |> Repo.update()
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
        Ecto.Changeset.change(changeset, status: "pending", decision_note: nil, decided_at: nil),
      else: changeset
  end
```

Two rules from Chapter 16 live here.

**Paid is final.** The first clause matches on `status: "paid"` and returns
`{:error, :paid}` without building a changeset at all. Once money has left
someone's M-Pesa account, the record of what it was for mustn't move.

**Changing the figures sends it back.** `reopen_if_changed/1` looks at
`changeset.changes`, which only holds fields whose value actually differs
from what's saved. If any of them is a figure the approver saw, the
transaction goes back to `"pending"`, and the old note and decision time are
cleared, because they were about a version that no longer exists.

You'll notice what's *not* in `@decided_fields`: `photo_path` and `source`.
Re-taking a blurry photo of the same receipt doesn't change what was
approved. And because `cast/3` drops values that equal what's saved, opening
the form on an approved expense and tapping **Save** without touching
anything keeps it approved. Only a real change reopens it.

`{:error, :paid}` is a new kind of error for `update_transaction/2`. Until
now it only returned changesets, and the form's `save/2` passes any error to
`changeset_errors/1`, which would crash on an atom. Nothing on the phone
marks a transaction paid yet, but sync will, so let's handle it now. In
`lib/risiti_app/screens/receipt_form_screen.ex`:

```elixir
    case result do
      {:ok, _saved} ->
        {:noreply, back_to_list(socket)}

      {:error, :paid} ->
        {:noreply, Native.toast(socket, "This one has been paid, so it can't change")}

      {:error, changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}
    end
```

A *toast*, remember, is Android's small message at the bottom of the
screen that fades on its own; we used one for the gallery in Chapter 15.

### Refunds

Next to it, add the two ways an expense becomes a refund and back:

```elixir
  @doc """
  Asks for an expense back: it becomes a refund, paid as `attrs` say, and
  waits for approval again.
  """
  def request_refund(%Transaction{type: "expense"} = transaction, attrs),
    do: update_transaction(transaction, Map.put(attrs, :type, "refund"))

  def request_refund(%Transaction{}, _attrs), do: {:error, :not_expense}

  @doc "A refund still waiting for a decision can be taken back: it becomes an expense again."
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
```

A refund isn't a new transaction. It's the expense you already recorded,
with a request attached: "I paid this myself, please pay me back". So
`request_refund/2` takes the expense and changes its type, through
`update_transaction/2`, which means every rule we just wrote applies. The
changeset sets `pay_to` to `"self"` and asks for a method. And because
`type` is one of the decided fields, an expense that was already approved
as spending goes back to pending: approving "we spent Ksh 3,450 at Naivas"
isn't the same as approving "pay Wanjiru Ksh 3,450".

`cancel_refund/1` undoes it, but only while nobody has decided. It clears
the payment details as it goes, so a cancelled refund doesn't keep a stale
phone number around. Once a refund is approved, cancelling it is a
conversation with the approver, not a button.

Both pattern-match on what they accept, in the function head, and return a
plain `{:error, reason}` for everything else. Screens can match on those
atoms, as the form now does with `:paid`.

### Decisions

Then the one function that records a decision:

```elixir
  @doc """
  Records a decision: `"approved"` or `"rejected"` (with an optional note),
  or `"paid"` once an approved claim has been paid. On the phone these will
  come from the server (Part IV); the function is the same either way.
  """
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
```

`DateTime.truncate/2` is there because the columns are `:utc_datetime`,
which stores whole seconds; Ecto refuses a datetime with microseconds for
one.

On the phone, `decide/3` has one real caller, and it doesn't exist yet: the
sync in Part IV, writing down what the server decided. Today it has another
caller, which is just as useful: our tests. They can now build an approved
or paid transaction in one line, and check what the rest of the app does
with it.

> A personal book, used by one person, has no approver. In the real app
> everything saved in one is approved on the spot. That needs to know which
> book you're in, which arrives with sign-in in Part IV, so for now every
> new transaction starts pending.

### What counts as spending

Last, the spend card. A rejected expense was refused: the team doesn't
consider it spent, and the month's total shouldn't either. In `summary/1`,
add one condition to the query:

```elixir
    per_category =
      Repo.all(
        from t in Transaction,
          where: t.date >= ^from and t.date <= ^to and t.status != "rejected",
          group_by: t.category,
          select: {t.category, sum(t.amount_cents)}
      )
```

And two pairs of labels, for the screens that show types and statuses in
the next chapters:

```elixir
  def type_label("expense"), do: "Expense"
  def type_label("refund"), do: "Refund"
  def type_label("payment_request"), do: "Payment request"

  def status_label("pending"), do: "Pending approval"
  def status_label("approved"), do: "Approved"
  def status_label("rejected"), do: "Rejected"
  def status_label("paid"), do: "Paid"
```

These sit next to `group_label/1`, which they look just like. Words for the
person live in the context; the screens ask for them. When the server says
`"payment_request"`, the phone says "Payment request", and there's one place
to change it.

## Run it

Deploy as usual:

```
mix mob.deploy --device YOUR_DEVICE_ID
```

Risiti opens looking exactly as it did. That's the first thing to check,
and the most important one: the receipts you saved in Part I are all still
there. The new migration ran at boot, added its columns around your data,
and went on.

Now let's look underneath. Connect with `mix mob.connect`, and in IEx:

```elixir
iex> node = hd(Node.list())
iex> [latest | _] = :rpc.call(node, RisitiApp.Transactions, :list_transactions, [])
iex> {latest.status, latest.client_id}
{"pending", "9f2c4e0a7b31d85e6c0f1a2b3c4d5e6f"}
```

A receipt saved before this chapter: pending, and with a `client_id` the
migration made for it, hex without dashes. Add a new one from the form, list
again, and its `client_id` has the dashes of `Ecto.UUID.generate/0`. Both
kinds work the same.

Then play approver from your laptop:

```elixir
iex> :rpc.call(node, RisitiApp.Transactions, :decide, [latest, "rejected", "Personal"])
{:ok, %RisitiApp.Transactions.Transaction{status: "rejected", ...}}
```

Close and reopen Risiti. The receipt is still in the list, since we haven't
taught the list about statuses yet, but the month's total on the spend card
has dropped by its amount. Edit its amount in the form and save, and run
`list_transactions` again: it's back to `"pending"`, with no note.

## Testing it

The rules in this chapter are the kind that break quietly. A wrong amount
paid out because an approval survived an edit isn't something you want to
find on a phone. So they get the most tests of any chapter so far, none of
which need one.

First the doctests. Create `test/risiti_app/phone_test.exs`:

```elixir
# test/risiti_app/phone_test.exs
defmodule RisitiApp.PhoneTest do
  use ExUnit.Case, async: true
  doctest RisitiApp.Phone
end
```

Then the claims and statuses. Create
`test/risiti_app/transactions/claims_test.exs`:

```elixir
# test/risiti_app/transactions/claims_test.exs
defmodule RisitiApp.Transactions.ClaimsTest do
  use ExUnit.Case, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Transactions

  setup :checkout_repo

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp payment(attrs) do
    Map.merge(
      %{
        type: "payment_request",
        date: ~D[2026-10-05],
        vendor: "Kamau Hardware",
        amount_cents: 1_250_000,
        category: "Office Supplies"
      },
      attrs
    )
  end

  defp refund do
    {:ok, refund} =
      Transactions.request_refund(insert_transaction(), %{
        method: "send_money",
        phone: "0712 345 678"
      })

    refund
  end

  describe "client_id" do
    test "every new transaction gets its own, for life" do
      a = insert_transaction()
      b = insert_transaction()

      assert {:ok, _} = Ecto.UUID.cast(a.client_id)
      assert a.client_id != b.client_id

      {:ok, edited} = Transactions.update_transaction(a, %{vendor: "Naivas Westlands"})
      assert edited.client_id == a.client_id
    end
  end

  describe "claims" do
    test "an expense pays nobody; a refund pays the person, by phone" do
      assert insert_transaction().pay_to == nil

      refund = refund()
      assert refund.type == "refund"
      assert refund.pay_to == "self"
      assert refund.phone == "+254712345678"
    end

    test "a payment request pays a supplier unless it's an advance" do
      {:ok, supplier} = Transactions.create_transaction(payment(%{method: "cash"}))

      {:ok, advance} =
        Transactions.create_transaction(payment(%{method: "cash", pay_to: "self"}))

      assert supplier.pay_to == "supplier"
      assert advance.pay_to == "self"
    end

    test "a claim must say how to pay" do
      {:error, changeset} = Transactions.create_transaction(payment(%{}))
      assert %{method: ["choose how to pay"]} = errors_on(changeset)
    end

    test "each way of paying asks for its own details" do
      {:error, till} =
        Transactions.create_transaction(payment(%{method: "till", till_number: "12"}))

      assert %{till_number: ["is 5 to 7 digits"]} = errors_on(till)

      {:error, paybill} =
        Transactions.create_transaction(payment(%{method: "paybill", paybill_number: "247247"}))

      assert %{account_number: ["enter the account number"]} = errors_on(paybill)

      {:error, phone} =
        Transactions.create_transaction(payment(%{method: "send_money", phone: "12345"}))

      assert %{phone: ["is not a valid Kenyan mobile number"]} = errors_on(phone)

      assert {:ok, _} =
               Transactions.create_transaction(
                 payment(%{
                   method: "paybill",
                   paybill_number: "247247",
                   account_number: "INV-204"
                 })
               )
    end

    test "only an expense can become a refund" do
      assert Transactions.request_refund(refund(), %{}) == {:error, :not_expense}
    end

    test "a pending refund can be taken back; a decided one can't" do
      {:ok, expense} = Transactions.cancel_refund(refund())
      assert expense.type == "expense"
      assert expense.method == nil
      assert expense.pay_to == nil

      {:ok, approved} = Transactions.decide(refund(), "approved")
      assert Transactions.cancel_refund(approved) == {:error, :not_pending}
    end
  end

  describe "status" do
    test "changing the figures of a decided transaction sends it back to pending" do
      {:ok, approved} = Transactions.decide(insert_transaction(), "approved", "Thanks")

      {:ok, untouched} = Transactions.update_transaction(approved, %{vendor: approved.vendor})
      assert untouched.status == "approved"

      {:ok, changed} = Transactions.update_transaction(approved, %{amount_cents: 99_900})
      assert changed.status == "pending"
      assert changed.decision_note == nil
      assert changed.decided_at == nil
    end

    test "a paid transaction can't be changed" do
      {:ok, approved} = Transactions.decide(refund(), "approved")
      {:ok, paid} = Transactions.decide(approved, "paid")

      assert paid.paid_at
      assert Transactions.update_transaction(paid, %{amount_cents: 1}) == {:error, :paid}
    end

    test "rejected spending doesn't count in the month's total" do
      insert_transaction(amount_cents: 100_000)

      {:ok, _} =
        Transactions.decide(insert_transaction(amount_cents: 50_000), "rejected", "Personal")

      assert Transactions.summary().total == 100_000
    end
  end
end
```

A few things worth pointing out:

- **`insert_transaction/1`** is the helper from Chapter 12. It goes through
  `create_transaction/1`, so every transaction in these tests gets its
  `client_id` the way the app gives it one. A helper that inserted rows
  directly would skip exactly the code we want to test.
- **`errors_on/1`** is the same helper Phoenix generates in `DataCase`,
  turning a changeset's errors into a map of plain messages we can match.
- **The first status test saves without changing anything** before it
  changes the amount. Its first half checks the quieter half of the rule: an
  edit that changes nothing doesn't throw an approval away.
- **The `decide/3` calls** are standing in for the server. Every status in
  these tests got there the way it will in Part IV, just without a network.

And one more test for the form, in `receipt_form_screen_test.exs`, to pin
down the new `{:error, :paid}` branch:

```elixir
  test "a paid transaction stays as it was paid" do
    {:ok, approved} = Transactions.decide(insert_transaction(amount_cents: 345_050), "approved")
    {:ok, paid} = Transactions.decide(approved, "paid")

    view =
      ReceiptFormScreen
      |> mount_screen(%{id: paid.id})
      |> fill_in(amount: "1")
      |> render_info({:tap, :save})

    assert navigated_to(view) == nil
    assert_received {:native, :toast, ["This one has been paid, so it can't change"]}
    assert Transactions.get_transaction!(paid.id).amount_cents == 345_050
  end
```

`assert_received {:native, :toast, ...}` works because of the test switch in
`RisitiApp.Native` from Chapter 14: under `mix test`, a native call becomes
a message to the test process instead of a call into Android.

```
mix test
```

```
3 doctests, 56 tests, 0 failures
```

## What we have so far

- A migration that grows a table people already have, filling in a
  `client_id` for every row that was there before it.
- One schema for three types, deciding who is paid and asking each way of
  paying for its own details.
- `RisitiApp.Phone`, for Kenyan numbers in one form.
- Two changesets, one for the figures and one for the decisions: the rule
  from Chapter 16, in code.
- A `client_id` given once, at creation, that nothing can change.
- A context that reopens a decided transaction whose figures change, keeps
  a paid one final, turns expenses into refunds and back, and leaves
  rejected spending out of the month.

The code at the end of this chapter is in `code/17/`.

All of this is invisible so far. The home screen still shows every row the
same way, with no hint of what's pending, refused or paid. In the next
chapter we finish the home screen: a month picker, search, date ranges, and
a transaction item that finally shows where each one stands.
