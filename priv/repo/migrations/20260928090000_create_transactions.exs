defmodule DukaApp.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  # Receipts, refund requests and payment requests become one table of
  # transactions, typed expense, refund or payment_request — the same move
  # the Risiti server makes, with the same ids and client ids, so the next
  # sync lines up:
  #
  #   * a receipt with a refund request becomes one refund, as its latest
  #     request was decided; other receipts become expenses;
  #   * payment requests (and any older refund requests for the same
  #     receipt) become transactions of their own, dated the day they were
  #     made, paying the payee, in "Other".
  #
  # The old tables stay, untouched, until a later version drops them.

  @latest_refund """
  SELECT q2.id FROM requests q2
  WHERE q2.receipt_id = q.receipt_id AND q2.kind = 'refund'
  ORDER BY q2.inserted_at DESC, q2.id DESC LIMIT 1
  """

  def up do
    create table(:transactions) do
      add :profile_id, references(:profiles, on_delete: :delete_all), null: false
      # "expense", "refund" or "payment_request".
      add :type, :string, null: false, default: "expense"
      # Who a refund or payment request pays: "self" or "supplier".
      add :pay_to, :string
      add :date, :date, null: false
      add :vendor, :string, null: false
      add :description, :string
      add :amount_cents, :integer, null: false
      add :category, :string, null: false

      # How it was, or is to be, paid, and the details that needs.
      add :method, :string
      add :phone, :string
      add :till_number, :string
      add :paybill_number, :string
      add :account_number, :string

      add :qr_content, :text
      add :source, :string, null: false, default: "manual"
      add :seller_pin, :string
      add :branch_id, :string
      add :invoice_number, :string
      add :verify_url, :text
      add :verified_at, :utc_datetime
      add :photo_path, :string
      add :ocr_text, :text

      # pending -> approved | rejected, and for claims approved -> paid.
      add :status, :string, null: false, default: "pending"
      add :decision_note, :string
      add :decided_at, :utc_datetime
      add :paid_at, :utc_datetime

      add :client_id, :string, null: false
      add :remote_id, :string
      add :needs_push, :boolean, null: false, default: true
      add :photo_pushed, :boolean, null: false, default: false
      add :synced_at, :utc_datetime

      timestamps()
    end

    create index(:transactions, [:profile_id, :date])
    create unique_index(:transactions, [:profile_id, :qr_content])
    create unique_index(:transactions, [:client_id])

    create table(:transaction_attachments) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      # Stored file name under the app's attachments directory.
      add :file_name, :string, null: false
      add :name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false
      # Its id on the server, once it's there.
      add :remote_id, :string

      timestamps()
    end

    create index(:transaction_attachments, [:transaction_id])

    alter table(:profiles) do
      add :can_approve, :boolean, null: false, default: false
      add :can_list_all, :boolean, null: false, default: false
      add :can_export, :boolean, null: false, default: false
    end

    flush()

    execute("""
    INSERT INTO transactions
      (id, profile_id, type, pay_to, date, vendor, description, amount_cents, category,
       method, phone, till_number, paybill_number, account_number,
       qr_content, source, seller_pin, branch_id, invoice_number, verify_url, verified_at,
       photo_path, ocr_text, status, decision_note, decided_at,
       client_id, remote_id, needs_push, photo_pushed, synced_at, inserted_at, updated_at)
    SELECT r.id, r.profile_id,
      CASE WHEN q.id IS NULL THEN 'expense' ELSE 'refund' END,
      CASE WHEN q.id IS NULL THEN NULL ELSE 'self' END,
      r.date, r.vendor, r.description, COALESCE(q.amount_cents, r.amount_cents), r.category,
      q.method, q.phone, q.till_number, q.paybill_number, q.account_number,
      r.qr_content, r.source, r.seller_pin, r.branch_id, r.invoice_number, r.verify_url,
      r.verified_at, r.photo_path, r.ocr_text,
      COALESCE(q.status, r.approval_status),
      CASE WHEN q.id IS NULL THEN r.approval_note ELSE q.decision_note END,
      CASE WHEN q.id IS NULL THEN r.decided_at ELSE q.decided_at END,
      r.client_id, r.remote_id,
      -- The server has it as it is here only if both halves were sent.
      CASE WHEN r.needs_push OR (q.id IS NOT NULL AND q.remote_id IS NULL) THEN 1 ELSE 0 END,
      r.photo_pushed, r.synced_at, r.inserted_at, r.updated_at
    FROM receipts r
    LEFT JOIN requests q ON q.receipt_id = r.id AND q.kind = 'refund' AND q.id = (#{@latest_refund})
    """)

    execute("""
    INSERT INTO transactions
      (profile_id, type, pay_to, date, vendor, description, amount_cents, category,
       method, phone, till_number, paybill_number, account_number, status, decision_note,
       decided_at, client_id, remote_id, needs_push, synced_at, inserted_at, updated_at)
    SELECT q.profile_id,
      CASE q.kind WHEN 'refund' THEN 'refund' ELSE 'payment_request' END,
      CASE q.kind WHEN 'refund' THEN 'self' ELSE 'supplier' END,
      COALESCE(r.date, date(q.inserted_at, '+3 hours')),
      COALESCE(r.vendor, NULLIF(q.payee_name, ''), q.phone, 'Till ' || q.till_number,
               'Paybill ' || q.paybill_number, 'Payment'),
      COALESCE(q.purpose, r.description), q.amount_cents, COALESCE(r.category, 'Other'),
      q.method, q.phone, q.till_number, q.paybill_number, q.account_number,
      q.status, q.decision_note, q.decided_at, q.client_id, q.remote_id,
      CASE WHEN q.remote_id IS NULL THEN 1 ELSE 0 END,
      q.synced_at, q.inserted_at, q.updated_at
    FROM requests q
    LEFT JOIN receipts r ON r.id = q.receipt_id
    WHERE NOT (q.kind = 'refund' AND q.receipt_id IS NOT NULL AND q.id = (#{@latest_refund}))
    """)

    # Each attachment follows its request: to the receipt's transaction for
    # a merged refund, otherwise to the request's own (found by client id).
    execute("""
    INSERT INTO transaction_attachments
      (transaction_id, file_name, name, content_type, size, remote_id, inserted_at, updated_at)
    SELECT t.id, a.file_name, a.name, a.content_type, a.size, a.remote_id,
      a.inserted_at, a.updated_at
    FROM request_attachments a
    JOIN requests q ON q.id = a.request_id
    LEFT JOIN receipts r ON r.id = q.receipt_id
    JOIN transactions t ON t.client_id =
      CASE WHEN q.kind = 'refund' AND q.receipt_id IS NOT NULL AND q.id = (#{@latest_refund})
           THEN r.client_id ELSE q.client_id END
    """)

    # Deletions still waiting for the server: both kinds are transactions now.
    execute("""
    UPDATE OR IGNORE sync_deletions SET kind = 'transaction' WHERE kind IN ('receipt', 'request')
    """)

    execute("DELETE FROM sync_deletions WHERE kind IN ('receipt', 'request')")

    execute("""
    UPDATE profiles SET can_approve = (can_approve_receipts OR can_approve_requests)
    """)
  end

  def down do
    alter table(:profiles) do
      remove :can_approve
      remove :can_list_all
      remove :can_export
    end

    drop table(:transaction_attachments)
    drop table(:transactions)
  end
end
