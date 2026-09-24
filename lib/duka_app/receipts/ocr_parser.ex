defmodule DukaApp.Receipts.OcrParser do
  @moduledoc """
  Pulls receipt fields out of OCR text: vendor, date, total, seller KRA PIN
  and invoice number. Every field is a best guess and may be nil; the user
  confirms them on the form.

  Expects the text one visual row per line (as `MobOcr` produces), so a
  label and its amount share a line. The rules are tuned to Kenyan eTIMS
  receipts, which print several "TOTAL" lines besides the real one:

      TOTAL                 2,450.00   <- the total
      CASH                  3,000.00
      CHANGE                  550.00
      TOTAL A-EX                0.00   <- per-tax-band totals: ignored
      TOTAL B-16.00%        2,112.07
      TOTAL TAX               337.93   <- ignored
  """

  @type result :: %{
          vendor: String.t() | nil,
          date: Date.t() | nil,
          amount_cents: pos_integer() | nil,
          seller_pin: String.t() | nil,
          invoice_number: String.t() | nil
        }

  @money ~r/(?<![\d.,])(\d{1,3}(?:[, ]\d{3})+|\d+)[.,](\d{2})(?![\d])/

  # Labels that name the amount paid, strongest first.
  @strong_total ~r/\b(GRAND\s*TOTAL|TOTAL\s+(AMOUNT|AMT|DUE|PAYABLE|KES|KSH|SALES?)|AMOUNT\s+(DUE|PAYABLE)|NET\s+(AMOUNT|TOTAL))\b/
  @plain_total ~r/\bTOTAL\b/
  # "TOTAL" lines that are not the amount paid: subtotals, tax-band and tax
  # totals, item counts, payment/change lines.
  @not_total ~r/SUB\s*-?\s*TOTAL|\bTAX\b|\bVAT\b|%|\bITEMS?\b|\bQTY\b|QUANTITY|DISCOUNT|SAVING|CHANGE|TENDER|\bCASH\b|TOTAL\s+[A-E]\s*[-–]|\bEX\b|EXEMPT/

  @kra_pin ~r/\b([AP]\d{9}[A-Z])\b/
  @buyer ~r/BUYER|CUSTOMER|CLIENT|PURCHASER/

  @invoice ~r/(?:CU\s*INV(?:OICE)?\.?\s*(?:NO|NUMBER)|INVOICE\s*(?:NO|NUMBER)|RECEIPT\s*(?:NO|NUMBER))\.?\s*[:#]?\s*([A-Z0-9][A-Z0-9\/-]{3,})/

  # Header lines that are not the business name.
  @not_vendor ~r/\bPIN\b|\bTEL\b|PHONE|MOBILE|\bBOX\b|P\.?\s*O\.?\b|RECEIPT|INVOICE|\bTAX\b|\bVAT\b|WELCOME|\bDATE\b|\bTIME\b|\bTILL\b|CASHIER|\bKRA\b|ETIMS|EMAIL|WWW|@|\.COM|\bSTREET\b|\bROAD\b|\bRD\b|\bBRANCH\b|\bCOPY\b/

  @months ~w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC)

  @spec parse(String.t(), keyword()) :: result()
  def parse(text, opts \\ []) when is_binary(text) do
    today = Keyword.get(opts, :today, DukaApp.Receipts.today())

    lines =
      text
      |> String.split(~r/\R/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    upper = Enum.map(lines, &String.upcase/1)

    %{
      vendor: vendor(lines, upper),
      date: date(upper, today),
      amount_cents: total(upper),
      seller_pin: seller_pin(upper),
      invoice_number: invoice_number(upper)
    }
  end

  # ── Total ─────────────────────────────────────────────────────────────────

  defp total(lines) do
    indexed = Enum.with_index(lines)

    Enum.find_value([@strong_total, @plain_total], fn label ->
      Enum.find_value(indexed, &labelled_amount(&1, label, lines))
    end)
  end

  defp labelled_amount({line, i}, label, lines) do
    if Regex.match?(label, line) and not Regex.match?(@not_total, line) do
      positive(last_amount(line) || first_amount(Enum.at(lines, i + 1)))
    end
  end

  defp positive(cents) when is_integer(cents) and cents > 0, do: cents
  defp positive(_), do: nil

  defp last_amount(line) do
    case Regex.scan(@money, line) do
      [] -> nil
      matches -> matches |> List.last() |> to_cents()
    end
  end

  defp first_amount(nil), do: nil

  defp first_amount(line) do
    case Regex.run(@money, line) do
      nil -> nil
      match -> to_cents(match)
    end
  end

  defp to_cents([_, shillings, cents]) do
    String.to_integer(String.replace(shillings, ~r/[, ]/, "")) * 100 + String.to_integer(cents)
  end

  # ── Date ──────────────────────────────────────────────────────────────────

  defp date(lines, today) do
    # A line that says DATE is the transaction date; anything else (an
    # expiry, a promo) is only a fallback.
    {dated, other} = Enum.split_with(lines, &String.contains?(&1, "DATE"))
    Enum.find_value(dated ++ other, &find_date(&1, today))
  end

  defp find_date(line, today) do
    candidates(line)
    |> Enum.find_value(fn {y, m, d} ->
      with {:ok, date} <- Date.new(y, m, d),
           true <- date.year >= 2000 and Date.compare(date, Date.add(today, 1)) != :gt do
        date
      else
        _ -> nil
      end
    end)
  end

  defp candidates(line) do
    month = Enum.join(@months, "|")

    iso =
      for [_, y, m, d] <- Regex.scan(~r/\b(20\d{2})[-\/.](\d{1,2})[-\/.](\d{1,2})\b/, line),
          do: {int(y), int(m), int(d)}

    day_first =
      for [_, d, m, y] <- Regex.scan(~r/\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4}|\d{2})\b/, line),
          do: {year(y), int(m), int(d)}

    named =
      for [_, d, mon, y] <-
            Regex.scan(~r/\b(\d{1,2})[\s\-\/.]*(#{month})[A-Z]*[\s\-\/.,]*(\d{4}|\d{2})\b/, line),
          do: {year(y), month_number(mon), int(d)}

    us_named =
      for [_, mon, d, y] <-
            Regex.scan(~r/\b(#{month})[A-Z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b/, line),
          do: {year(y), month_number(mon), int(d)}

    iso ++ day_first ++ named ++ us_named
  end

  defp int(s), do: String.to_integer(s)
  defp year(<<_, _>> = yy), do: 2000 + int(yy)
  defp year(yyyy), do: int(yyyy)
  defp month_number(mon), do: Enum.find_index(@months, &(&1 == mon)) + 1

  # ── PIN, invoice, vendor ────────────────────────────────────────────────

  defp seller_pin(lines) do
    lines
    |> Enum.reject(&Regex.match?(@buyer, &1))
    |> Enum.find_value(fn line ->
      case Regex.run(@kra_pin, line) do
        [_, pin] -> pin
        nil -> nil
      end
    end)
  end

  defp invoice_number(lines) do
    Enum.find_value(lines, fn line ->
      case Regex.run(@invoice, line) do
        [_, number] -> number
        nil -> nil
      end
    end)
  end

  # The business name is printed first, usually in capitals. Take the first
  # of the top lines that is mostly letters and is not an address, phone,
  # PIN or document-title line.
  defp vendor(lines, upper) do
    lines
    |> Enum.zip(upper)
    |> Enum.take(8)
    |> Enum.find_value(fn {line, up} ->
      if vendor_like?(up) and not Regex.match?(@not_vendor, up), do: tidy_vendor(line)
    end)
  end

  defp vendor_like?(line) do
    letters = line |> String.replace(~r/[^A-Z]/, "") |> String.length()
    visible = line |> String.replace(~r/\s/, "") |> String.length()
    letters >= 3 and visible <= 60 and letters / visible >= 0.6
  end

  defp tidy_vendor(line) do
    line = line |> String.replace(~r/\s{2,}/, " ") |> String.trim(" *-=")

    if line == String.upcase(line) do
      line
      |> String.split(" ")
      |> Enum.map_join(" ", &title_word/1)
    else
      line
    end
  end

  # Short all-caps words are usually abbreviations (LTD is not, but KFC, EABL
  # and TMC are); keep those as they are.
  defp title_word(word) when byte_size(word) <= 3 and word not in ~w(LTD THE AND), do: word
  defp title_word(word), do: String.capitalize(word)
end
