# Chapter 21: Refunds, Payment Requests and Attachments

Previously, Risiti learned to trust KRA. A scanned eTIMS receipt arrives
filled in from the tax authority's own record, and saved receipts are
checked in the background. Every receipt Risiti holds is now as reliable as
we can make it.

But every one of them is still an expense: money already spent, recorded
for the books. Back in Chapter 16 we said Risiti handles three types of
transaction, and Chapter 17 gave the table everything the other two need:
who is paid, how, and where the decision stands. In this chapter, the
screens catch up. People can ask for their money back, and ask the team to
pay someone.

By the end of this chapter, you will know:

- How one record changes type, from an expense to a refund and back.
- How a payment request asks for exactly the details its way of paying
  needs.
- How to attach invoices and quotations, as photos or PDFs, picked from
  the phone.
- How a screen that's popped back to learns that something changed.
- What editing a request after sending it does to its approval.

## Turning an expense into a refund

Here's the situation a refund is for. Wanjiru takes a client to lunch at
Java House and pays with her own M-Pesa, because the company card is with
someone else. She photographs the receipt in Risiti, and now she wants the
Ksh 960 back.

The receipt is already in Risiti as an expense. A refund isn't a second
record; it's the same expense, with a request attached: "I paid this
myself, please pay me back". Chapter 17 built exactly that in the context:

```elixir
  def request_refund(%Transaction{type: "expense"} = transaction, attrs),
    do: update_transaction(transaction, Map.put(attrs, :type, "refund"))
```

Same row, same `client_id`, new type. The changeset sets `pay_to` to
`"self"` and asks for a way of paying, and because the type is one of the
figures an approver sees, the transaction goes back to pending if it had
been approved as an expense.

Why the same row and not a new one? Because otherwise the same Ksh 960
would be in the books twice, once as the expense and once as the refund,
and the month's total on the spend card would double-count it. One receipt,
one transaction, whatever is asked of it.

### From the sheet

The details sheet from Chapter 18 offers it. In
`lib/risiti_app/components/transaction_sheet.ex`, below the KRA button:

```elixir
        {refund_button(transaction)}
```

```elixir
  # An expense can be claimed back; a refund still waiting can be taken back.
  defp refund_button(%{type: "expense", status: status}) when status != "paid" do
    ~MOB"""
    <Column fill_width={true} padding_top={8}>
      {ActionButton.button(nil, "Request refund", :request_refund, style: :secondary)}
    </Column>
    """
  end

  defp refund_button(%{type: "refund", status: "pending"}) do
    ~MOB"""
    <Column fill_width={true} padding_top={8}>
      {ActionButton.button("close", "Take back refund request", :cancel_refund, style: :secondary)}
    </Column>
    """
  end

  defp refund_button(_transaction), do: []
```

The function heads say the rules. An expense can be claimed back unless
it's been paid. A refund can be taken back only while it's pending. Every
other combination shows nothing.

**Request refund** opens a form, which we'll build in a moment:

```elixir
  def handle_info({:tap, :request_refund}, socket) do
    %{id: id} = socket.assigns.selected

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(RequestFormScreen, %{refund_of: id, notify: self()})}
  end
```

Note the `notify: self()`. We'll come back to it.

### Taking it back

People change their minds, or find the company card was used after all.
While nobody has decided on a refund, it can be taken back, and Chapter
17's `cancel_refund/1` turns it into an expense again and clears the
payment details. It's a decision the person should confirm, so it asks
first:

```elixir
  def handle_info({:tap, :cancel_refund}, socket) do
    {:noreply,
     Native.alert(socket,
       title: "Take back the refund request?",
       message: "It stays as an expense, and nobody will pay it back.",
       buttons: [
         [label: "Take back", style: :destructive, action: :confirm_cancel_refund],
         [label: "Keep", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_cancel_refund}, %{assigns: %{selected: %{} = refund}} = socket) do
    case Transactions.cancel_refund(refund) do
      {:ok, expense} ->
        {:noreply,
         socket
         |> Native.toast("Refund request taken back")
         |> Mob.Socket.assign(:selected, expense)
         |> load_receipts()}

      {:error, :not_pending} ->
        {:noreply, Native.toast(socket, "It has been decided on, so it stays")}
    end
  end
```

The message says what *stays*, not just what goes. "It stays as an
expense" answers the worry people actually have: did I just delete my
receipt?

The sheet stays open on the transaction, now an expense again, so the
person sees the change and the **Request refund** button comes back.

## Payment requests

The other kind of claim asks the team to pay someone. The site needs
cement; the supplier wants payment before delivery; the person on the
ground can't pay Ksh 12,500 from their own pocket. So they ask, and
someone with the money approves and pays.

A payment request has no receipt yet. It has an amount, a payee, a reason,
and above all, *how to pay*. In Kenya that nearly always means M-Pesa, in
one of three ways:

| Way | What the payer needs | Typical for |
|---|---|---|
| **Send money** | A phone number | A person: a fundi, a driver, yourself |
| **Buy Goods (till)** | A till number | A shop or a small business |
| **Paybill** | A paybill number and an account number | A company: KPLC, a supplier with an account |

Chapter 17's changeset already checks each of these: a valid Kenyan
number, a till of five to seven digits, a paybill and an account. The form
just has to ask for the right ones.

### One form, three jobs

Requesting a payment, requesting a refund and editing a request share most
of their fields, so they're one screen with three modes, decided by the
mount params. Create `lib/risiti_app/screens/request_form_screen.ex`. The
full file is in `code/21`; here are the parts that matter.

```elixir
  @impl Mob.Screen
  def mount(params, _session, socket) do
    {mode, draft} = draft(params)

    socket =
      socket
      |> Mob.Socket.assign(mode: mode, draft: draft, notify: params[:notify], errors: %{})
      |> Mob.Socket.assign(inputs(mode, draft))
      # New ones, copied in as soon as they're added (see Attachments), and
      # deleted again if the request is never sent.
      |> Mob.Socket.assign(:attachments, [])

    {:ok, socket}
  end

  defp draft(%{refund_of: id}), do: {:refund, Transactions.get_transaction!(id)}
  defp draft(%{id: id}), do: {:edit, Transactions.get_transaction!(id)}
  defp draft(_params), do: {:new, Transactions.new_payment()}
```

`Transactions.new_payment/0` is a draft with sensible defaults:

```elixir
  @doc "A draft payment request: to a supplier, by M-Pesa send money, until the person says otherwise."
  def new_payment do
    %Transaction{
      type: "payment_request",
      pay_to: "supplier",
      method: "send_money",
      date: today(),
      category: "Other",
      attachments: []
    }
  end
```

`inputs/2` turns the draft into the strings the fields hold, the same idea
as the receipt form's mount in Chapter 13. A stored phone number,
`+254712345678`, goes back to the way people type it, `0712345678`.

The top of the form depends on the mode. A refund shows the expense it's
for, which can't change here: the amount is what was spent. A payment asks
for the amount, the payee, what it's for, and its category, then who it
pays:

```elixir
      <Text text="This pays" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true} gap={8}>
        {pill("A supplier", {:pay_to, "supplier"}, @pay_to == "supplier")}
        {pill("Me (an advance)", {:pay_to, "self"}, @pay_to == "self")}
      </Row>
```

"Me (an advance)" is for money someone needs before they spend it: fuel
for a trip, cash for a site visit. Chapter 16 called it an advance, and so
does the button.

### Asking for the right details

Then the way of paying, as three pills, and below them only the fields
that way needs:

```elixir
  defp pay_with(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      <Text text="Pay with" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true} gap={8}>
        {Enum.map(methods(), &pill(method_label(&1), {:method, &1}, &1 == @method))}
      </Row>
      <Spacer size={16} />
      {method_fields(assigns)}
      <Spacer size={4} />
      {attachments_section(@draft.attachments, @attachments)}
    </Column>
    """
  end

  # Inside ~MOB, @methods would be an assign, so the list comes from a function.
  defp methods, do: @methods
```

That comment is worth a moment. The module has `@methods ~w(send_money
till paybill)`, and inside a `~MOB` template, as inside HEEx, `@name`
means "the assign called name". So `@methods` there would look for an
assign that doesn't exist. A one-line private function is the usual way
round it.

`method_fields/1` has a clause per method:

```elixir
  defp method_fields(%{method: "till"} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Till number",
        key: :till_number,
        value: @till_number,
        placeholder: "e.g. 832909",
        keyboard: :number,
        error: @errors[:till_number]
      )}
    </Column>
    """
  end
```

Send money gets a phone field with the phone keyboard; paybill gets two
fields. Each uses `keyboard: :number` or `:phone`, so the right keypad
comes up, as Chapter 13 showed.

When the person switches method, the fields switch too, but what they
typed in the old ones is still in the assigns. That's deliberate: switch
to Till and back to Send money, and the phone number is still there. But
only the chosen method's fields should be saved:

```elixir
  def build_attrs(assigns) do
    case Transactions.parse_amount(assigns.amount) do
      {:ok, cents} ->
        blank = %{phone: nil, till_number: nil, paybill_number: nil, account_number: nil}

        method_attrs =
          case assigns.method do
            "send_money" -> Map.take(assigns, [:phone])
            "till" -> Map.take(assigns, [:till_number])
            "paybill" -> Map.take(assigns, [:paybill_number, :account_number])
          end

        {:ok,
         blank
         |> Map.merge(method_attrs)
         |> Map.merge(%{
           type: "payment_request",
           pay_to: assigns.pay_to,
           date: assigns.draft.date,
           amount_cents: cents,
           vendor: assigns.vendor,
           description: assigns.description,
           category: assigns.category,
           method: assigns.method,
           source: "manual"
         })}

      :error ->
        {:error, %{amount: "enter an amount like 2500 or 2,500.50"}}
    end
  end
```

`blank` sets every payment field to `nil` first, and the chosen method's
fields overwrite theirs. A request edited from send money to paybill loses
its phone number in the database, so nobody pays it to a number nobody
meant.

### Errors in words

The changeset's messages were written in Chapter 17 to read well on their
own: "enter the till number", "is 5 to 7 digits". The form makes the
second kind into a sentence:

```elixir
  # "enter the till number" reads fine alone; "is 5 to 7 digits" needs its
  # field in front.
  defp message_for(field, "is " <> _ = message), do: "#{humanize(field)} #{message}"
  defp message_for(_field, message), do: String.capitalize(message)
```

So a till of "12" says "Till number is 5 to 7 digits" under the till field,
and a missing account number says "Enter the account number" under its
own.

### Sending

```elixir
  def handle_info({:tap, :submit}, socket) do
    with {:ok, attrs} <- build_attrs(socket.assigns),
         {:ok, saved} <- save(socket.assigns, attrs) do
      if pid = socket.assigns.notify, do: send(pid, {:request_saved, saved})

      {:noreply,
       socket
       |> Native.toast(saved_message(socket.assigns.mode))
       |> Mob.Socket.pop_screen()}
    else
      {:error, :paid} ->
        {:noreply, Native.toast(socket, "It has been paid, so it can't change")}

      {:error, :not_expense} ->
        {:noreply, Native.toast(socket, "A refund was already requested for it")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}

      {:error, errors} ->
        {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end
```

A `with` reads the happy path top to bottom and collects every way it can
fail in the `else`. Each error shape comes from somewhere specific:
`:paid` from `update_transaction/3`, `:not_expense` from
`request_refund/2`, a changeset from validation, and a plain map from
`build_attrs/1`'s amount check.

`save/2` has a clause per mode:

```elixir
  defp save(%{mode: :new, attachments: files}, attrs),
    do: Transactions.create_transaction(attrs, files)

  # Compared with the row as it's saved, as the receipt form does.
  defp save(%{mode: :edit, draft: draft, attachments: files}, attrs),
    do: Transactions.update_transaction(Transactions.get_transaction!(draft.id), attrs, files)

  defp save(%{mode: :refund, draft: expense}, attrs),
    do: Transactions.request_refund(expense, attrs)
```

### Telling the screen underneath

Now `notify`. The receipt form, since Chapter 13, goes back to the list
with `reset_to/4`, which throws away the navigation stack and mounts a
fresh home screen. That's fine for the receipt form; it only ever returns
there.

The request form is opened from the home screen, but also from the home
screen's *sheet*, and the person may have a search or a date period
showing. Resetting would throw all of that away. So the request form
*pops*, and the home screen underneath carries on exactly as it was:
same search, same period, same sheet closed behind it.

The catch is that a screen you pop back to doesn't mount again. In
LiveView terms, there's no new `mount/3` and nothing re-runs the queries,
so the list would show the transaction as it was before. The answer is
the same message-passing we used for the date screen in Chapter 18: the
home screen passes its pid as `notify`, and the form sends it
`{:request_saved, saved}` before popping. The home screen reloads:

```elixir
  # The request form pops back here, and this screen carries on as it was,
  # so the form tells it to reload.
  def handle_info({:request_saved, _transaction}, socket),
    do: {:noreply, load_receipts(socket)}
```

That's two patterns for returning to a screen, and it's worth knowing when
each fits. `reset_to/4` when the place you return to is always the same
fresh screen. Pop and notify when the person should come back to exactly
where they were.

### Getting there

On the home screen, **Add** now offers both kinds of new transaction:

```elixir
  def handle_info({:tap, :add_menu}, socket) do
    {:noreply,
     Native.action_sheet(socket,
       title: "Add",
       buttons: [
         [label: "Add an expense by hand", action: :add_manual],
         [label: "Request a payment", action: :new_payment],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({event, :add_manual}, socket) when event in [:tap, :alert] do
    {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen)}
  end

  def handle_info({:alert, :new_payment}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RequestFormScreen, %{notify: self()})}
  end
```

The dock's Add button sends `:add_menu` instead of `:add_manual`. The
`{event, :add_manual}` clause handles the old tap and the sheet's answer
alike, so nothing that sent `:add_manual` before breaks.

And the fifth pill Chapter 18 promised, **Refunds & payments**, joins the
group pills. In the context, a filter clause and a label:

```elixir
  defp filtered(query, :claims), do: from(t in query, where: t.type in ["refund", "payment_request"])
```

```elixir
  def group_label(:claims), do: "Refunds & payments"
```

and in `chips/2`, the list of pills gets `:claims` at the end:

```elixir
      ([{:all, "All · #{count}"}] ++
         Enum.map(Transactions.groups() ++ [:claims], &{&1, Transactions.group_label(&1)}))
```

`groups/0` stays the three spending groups, because the spend card splits
by those; claims are a filter on the list, not a fourth kind of spending.

## Attachments

A payment request often comes with a document: the supplier's quotation,
an invoice, a photo of the broken part. An approver deciding whether to
send Ksh 12,500 wants to see it. So a request can carry up to five
attachments, each an image or a PDF.

### A table of their own

A transaction has one receipt photo (`photo_path`) but any number of
attachments, so they get a table:

```elixir
# priv/repo/migrations/20261009090000_create_transaction_attachments.exs
defmodule RisitiApp.Repo.Migrations.CreateTransactionAttachments do
  use Ecto.Migration

  def change do
    create table(:transaction_attachments) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      # Stored file name in the app's attachments folder.
      add :file_name, :string, null: false
      # The name the person knows it by: "Invoice 2041.pdf".
      add :name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps()
    end

    create index(:transaction_attachments, [:transaction_id])
  end
end
```

`on_delete: :delete_all` removes the rows when their transaction goes. The
files on disk are another matter, which the context handles.

There are two names for each file. `file_name` is ours: unique, safe,
something like `attachment-1791269553374-589418.pdf`. `name` is the
person's: "Quotation from Kamau.pdf". We store files under our name,
because two suppliers can both send "invoice.pdf", and show them under
theirs.

The schema, `RisitiApp.Transactions.Attachment`, is a plain
`schema "transaction_attachments"` with those fields and
`belongs_to :transaction`, and `Transaction` gets the other side:

```elixir
    has_many :attachments, RisitiApp.Transactions.Attachment
```

### Files, copied in at once

`RisitiApp.Transactions.Attachments` looks after the files, the way
`Photos` has looked after receipt photos since Chapter 14. The central
function copies a file in:

```elixir
  # Enough for a phone photo or a scanned invoice of several pages.
  @max_size 10 * 1024 * 1024
  @max_count 5

  @doc """
  Copies the file at `source` in and returns an unsaved attachment for it.
  `name` is what to show; `content_type` must be an image or a PDF.
  """
  def store(source, name, content_type) do
    with :ok <- check_type(content_type),
         {:ok, %File.Stat{size: size}} <- File.stat(source),
         :ok <- check_size(size) do
      file_name =
        "attachment-#{System.os_time(:millisecond)}-#{:rand.uniform(1_000_000)}" <>
          extension(name, content_type)

      with :ok <- File.cp(source, path(file_name)) do
        {:ok,
         %Attachment{file_name: file_name, name: name, content_type: content_type, size: size}}
      end
    end
  end
```

It returns an `%Attachment{}` that isn't in the database yet. Why copy the
file before the request is saved? Because the picker's and the camera's
copies are temporary. The picker hands the app a copy of the file the
person chose, in a temporary folder, and the camera's photo sits in the
app's cache; both can be cleared at any time. If we waited
for **Send request**, the file might already be gone. So it's copied the
moment it's added, and if the request is never sent, the form deletes the
copy.

The rest of the module is small: `path/1`, `delete/1`, a
`content_type/1` that guesses from the file name when nobody said, and
`format_size/1` for "2.3 MB". Both of the last two have doctests.

### Saving them with the transaction

`create_transaction` and `update_transaction` take the new attachments as
an optional last argument, and insert them in the same database
transaction:

```elixir
  def create_transaction(attrs, attachments \\ []) do
    changeset = Transaction.changeset(%Transaction{client_id: Ecto.UUID.generate()}, attrs)

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, transaction} -> with_attachments(transaction, attachments)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Saves the new attachments against `transaction`, in the same database
  # transaction, and returns it with all of them.
  defp with_attachments(transaction, attachments) do
    Enum.each(attachments, &Repo.insert!(%{&1 | transaction_id: transaction.id}))
    Repo.preload(transaction, :attachments, force: true)
  end
```

`Repo.transaction/1` returns `{:ok, value}` with whatever the function
returns, or `{:error, value}` with whatever was passed to
`Repo.rollback/1`. So the function's result has the same shape as
`Repo.insert/1`'s, `{:ok, transaction}` or `{:error, changeset}`, and the
callers didn't have to change.

Either the request and all its attachments are saved, or none of them are.
A request whose quotation silently failed to save would be approved
without anyone seeing the quotation.

`update_transaction/3` does the same around `Repo.update/1`, after the
paid check and `reopen_if_changed/1`. And `delete_transaction/1` now
deletes the attachment files along with the receipt photo, after the rows
are gone:

```elixir
  def delete_transaction(%Transaction{} = transaction) do
    attachments = transaction |> Repo.preload(:attachments) |> Map.fetch!(:attachments)

    with {:ok, deleted} <- Repo.delete(transaction) do
      RisitiApp.Receipts.Photos.delete(deleted.photo_path)
      Attachments.delete(attachments)
      {:ok, deleted}
    end
  end
```

`list_transactions/3` and `get_transaction/1` preload the attachments, so
the sheet can list them.

### Picking them

The form offers two ways to add one: take a photo, or pick a file. The
picker is part of Mob, `Mob.Files`, and needs no permission at all,
because the person chooses each file in Android's own picker. Through
`Native`:

```elixir
  @doc """
  Opens the phone's file picker for images and PDFs. Replies
  `{:files, :picked, items}` or `{:files, :cancelled}` (see `Mob.Files`).
  """
  def pick_files(socket),
    do: call(socket, :pick_files, [], &Mob.Files.pick(&1, types: [:images, :pdf]))
```

Each picked item is a map with the file's temporary `path`, its `name`,
its `mime` type and its `size`. The form turns them into
`{path, name, type}` and adds them:

```elixir
  def handle_info({:files, :picked, items}, socket) do
    files =
      Enum.map(items, fn item ->
        name = item[:name] || "File"
        {item[:path], name, picked_type(item[:mime], name)}
      end)

    {:noreply, add_attachments(socket, files)}
  end

  # Trust a specific type from the picker; otherwise go by the name.
  defp picked_type(mime, name) when mime in [nil, "", "application/octet-stream"],
    do: Attachments.content_type(name)

  defp picked_type(mime, _name), do: mime
```

`application/octet-stream` is "some bytes, I don't know what". Some
pickers say that for everything from certain apps, so it counts as not
knowing.

The `types: [:images, :pdf]` filter narrows what the picker offers, but
Mob's docs are honest that Android filters by MIME type only, so it can't
promise. `add_attachments/2` checks again, and stops at the limit:

```elixir
  # Copies each file in, up to the limit, and says what couldn't be added.
  defp add_attachments(socket, files) do
    %{draft: draft, attachments: added} = socket.assigns
    room = Attachments.max_count() - length(draft.attachments) - length(added)
    {fits, over} = Enum.split(files, max(room, 0))

    {stored, problems} =
      Enum.reduce(fits, {[], []}, fn file, {stored, problems} ->
        case store(file) do
          {:ok, attachment} -> {[attachment | stored], problems}
          {:error, problem} -> {stored, [problem | problems]}
        end
      end)

    problems =
      Enum.reverse(problems) ++
        if(over == [], do: [], else: ["Only #{Attachments.max_count()} attachments fit"])

    socket = Mob.Socket.assign(socket, :attachments, added ++ Enum.reverse(stored))

    case problems do
      [] -> socket
      _ -> Native.toast(socket, Enum.join(problems, ". "))
    end
  end
```

Pick six files and five are added, with one toast that says why the sixth
wasn't. Pick a PDF and a text file and the PDF is added, with a toast
about the text file. One bad file never costs the person the good ones.

New attachments are listed with a remove button; ones already saved with
the request are listed without one. Removing a saved attachment would be a
change the approver needs to see, and that's a feature for another day.

And when the person backs out without sending, the copies go:

```elixir
  # Files copied in for a request that's never sent go too.
  def handle_info({:tap, :back}, socket) do
    Attachments.delete(socket.assigns.attachments)
    {:noreply, Mob.Socket.pop_screen(socket)}
  end
```

### Opening them

In the sheet, `TransactionItem.details/1` lists a transaction's
attachments, each a row that sends `{:tap, {:open_attachment, id}}`. The
home screen opens the file in whatever the phone uses for that type, a PDF
reader or the gallery:

```elixir
  def handle_info({:tap, {:open_attachment, id}}, %{assigns: %{selected: %{} = selected}} = socket) do
    case Enum.find(selected.attachments, &(&1.id == id)) do
      nil -> {:noreply, socket}
      attachment -> {:noreply, Native.open_file(socket, Attachments.path(attachment.file_name))}
    end
  end
```

```elixir
  @doc "Opens a file from the app's storage in the phone's own viewer: a PDF reader, the gallery."
  def open_file(socket, path),
    do:
      call(socket, :open_file, [path], fn socket ->
        Mob.Device.open_url(path)
        socket
      end)
```

Risiti doesn't need its own PDF viewer. The phone has a good one.

## Editing after sending

A payment request can be edited after it's sent: the supplier revised the
quotation, the till number was wrong. On the sheet, **Edit** on a payment
request opens the request form instead of the receipt form:

```elixir
  # A payment request is edited where it was made; anything else on the
  # receipt form.
  def handle_info({:tap, :edit_transaction}, socket) do
    %{id: id, type: type} = socket.assigns.selected

    {screen, params} =
      if type == "payment_request",
        do: {RequestFormScreen, %{id: id, notify: self()}},
        else: {ReceiptFormScreen, %{id: id}}

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(screen, params)}
  end
```

What happens to the approval is Chapter 17's rule, unchanged, because the
form saves through the same `update_transaction/3`: if any figure the
approver saw changes, the request goes back to pending, and the old note
and decision time are cleared. Change the amount of an approved request
from Ksh 12,500 to Ksh 13,000 and it's waiting for approval again. Change
nothing and press Save, and it stays approved. A paid request can't be
edited at all, and the sheet doesn't offer to.

This is the payoff of putting the rules in the context rather than in the
screens. Three screens now change transactions (the receipt form, the
request form, the home screen's refund actions), and not one of them knows
the approval rules. They can't get them wrong.

## Personal books

Not everyone using Risiti has a team. Plenty of people use it alone, to
keep their own spending straight, or a sole trader keeping receipts for
KRA. For them, refunds and payment requests make no sense: there's nobody
to ask, and nobody to approve.

The real Risiti hides all of this in a **personal book**. There, Add goes
straight to the receipt form with no menu, the sheet offers no refund, the
Refunds & payments pill isn't shown, and nothing says "waiting for
approval", because everything saved is approved on the spot.

Whether a book is personal is a fact about the person's account, which
comes with signing in. That's Part IV. Until then the phone app acts as a
business book, and we'll add the personal-book switches when there's an
account to read them from.

## Run it

```
mix mob.deploy --device YOUR_DEVICE_ID
```

Tap **Add** and choose **Request a payment**. Fill in an amount, a payee
and a reason, pick **Till**, enter a till number, and attach a quotation
with **Add file**:

<!-- SHOT: the request form: amount 12,500, Kamau Hardware, Cement for the site, Office Supplies, A supplier selected, Till selected with 832909, one PDF attachment "Quotation.pdf". -->
![Requesting a payment](images/21-request-form.png)

Send it, and it's on the list, with an amber tick: a claim waiting for a
decision. Tap the **Refunds & payments** pill to see only claims.

Now open an expense you paid yourself, tap **Request refund**, and enter
your M-Pesa number:

<!-- SHOT: the refund form for the Java House expense: "Refund for Java House", the amount, a note, the M-Pesa number field. -->
![Requesting a refund](images/21-refund-form.png)

Open the refund's sheet afterwards. It says "Refund" above the amount,
"Pay with M-Pesa 0712 345 678", "Pay to You", and offers to take the
request back.

Nobody can approve any of these yet. That's the server's job, and Part III
builds it.

## Testing it

The screens get `test/risiti_app/screens/claims_flow_test.exs`. A few
tests show something new. First, the whole payment request, down to what
was saved and the message back to the home screen:

```elixir
    test "a request to pay a supplier's till is saved, pending, and reported back" do
      view =
        RequestFormScreen
        |> mount_screen(%{notify: self()})
        |> fill_in(amount: "12,500", vendor: "Kamau Hardware", description: "Cement for the site")
        |> render_info({:tap, {:method, "till"}})
        |> fill_in(till_number: "832909")
        |> render_info({:tap, :submit})

      assert view.socket.__mob__.nav_action == {:pop}
      assert_received {:request_saved, %{type: "payment_request"}}
      assert_received {:native, :toast, ["Request sent for approval"]}

      assert [request] = Transactions.list_transactions()

      assert %{
               type: "payment_request",
               pay_to: "supplier",
               status: "pending",
               amount_cents: 1_250_000,
               method: "till",
               till_number: "832909"
             } = request
    end
```

The test passes itself as `notify`, as in Chapter 18, and receives
`{:request_saved, _}` in its own mailbox.

The refund test checks the thing that makes a refund a refund: it's the
same transaction.

```elixir
      assert %{
               type: "refund",
               pay_to: "self",
               phone: "+254712345678",
               description: "Client lunch — Paid with my own M-Pesa",
               client_id: client_id
             } = Transactions.get_transaction!(id)

      assert client_id == expense.client_id, "a refund is the same transaction"
```

The message on that last assertion is printed only if it fails. When a
test checks a design decision rather than an obvious fact, say what the
decision is, so whoever breaks it later knows what they broke.

And the attachments, with real files in a temporary folder (ExUnit's
`@tag :tmp_dir`, which we've used since Chapter 14):

```elixir
    @tag :tmp_dir
    test "picked files are copied in and saved with the request", context do
      view =
        RequestFormScreen
        |> mount_screen()
        |> fill_in(amount: "12,500", vendor: "Kamau Hardware", phone: "0712345678")
        |> render_info({:tap, :attach_file})

      assert_received {:native, :pick_files, []}

      view =
        render_info(
          view,
          {:files, :picked,
           [
             picked(context, "Quotation.pdf", "application/pdf"),
             picked(context, "notes.txt", "text/plain")
           ]}
        )

      assert [%{name: "Quotation.pdf", file_name: file_name}] = assigns(view).attachments
      assert File.read!(Attachments.path(file_name)) == "contents of Quotation.pdf"
      assert_received {:native, :toast, ["notes.txt isn't an image or PDF"]}

      render_info(view, {:tap, :submit})

      assert [%{attachments: [%{name: "Quotation.pdf", content_type: "application/pdf"}]}] =
               Transactions.list_transactions()
    end
```

`picked/3` writes a small file and returns the map the picker would send.
The test then follows the file all the way: copied in under our name,
the text file turned away with a toast, and the PDF saved against the
request.

The file also covers the add menu, switching methods, the errors in
words, an advance, editing an approved request (back to pending), taking a
refund back, the Refunds & payments pill, the five-file limit, files left
behind by a request never sent, and opening and deleting attachments from
the sheet. The request form's modes join `all_screens_test.exs`, and
`Attachments`' doctests run from `claims_test.exs`.

```
mix test
```

```
21 doctests, 131 tests, 0 failures
```

## What we have so far

- A refund that's the same transaction as its expense, requested from the
  sheet and taken back while nobody has decided.
- Payment requests to a supplier or as an advance, asking for exactly what
  send money, a till or a paybill needs, and saving only that.
- Attachments: images and PDFs, copied in when added, saved with the
  request in one database transaction, opened in the phone's own viewer.
- Two ways back to a screen: `reset_to/4`, and pop and notify.
- Editing a sent request, with the approval rules still in one place.
- A Refunds & payments pill on the home screen.

The code at the end of this chapter is in `code/21/`.

Everything in Risiti so far is built from Mob's own components and the
plugins it ships. In the next chapter, we write a plugin of our own from
nothing, Elixir to Zig to Kotlin and back, and use it to sign in with
Google.
