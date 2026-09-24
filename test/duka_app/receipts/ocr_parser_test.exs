defmodule DukaApp.Receipts.OcrParserTest do
  use ExUnit.Case, async: true

  alias DukaApp.Receipts.OcrParser

  @today ~D[2026-09-23]

  # Rows as MobOcr rebuilds them from an eTIMS supermarket receipt.
  @etims_supermarket """
  NAIVAS LIMITED
  NAIVAS WESTLANDS
  P.O BOX 61600-00200 NAIROBI
  TEL: 0709 800 000
  PIN: P051234567X
  TAX INVOICE
  Brookside Milk 500ml  2  130.00
  Sugar 2kg  1  320.00
  Bread  1  65.00
  TOTAL  2,450.00
  CASH  3,000.00
  CHANGE  550.00
  TOTAL A-EX  0.00
  TOTAL B-16.00%  2,112.07
  TOTAL TAX B  337.93
  TOTAL TAX  337.93
  ITEMS NUMBER  3
  Date: 21/09/2026  Time: 14:32:10
  SCU INFORMATION
  CU INVOICE NO.: KRACU0100012345/1234
  Receipt Signature: JHEURBU6RQAMEF3Y
  """

  test "reads an eTIMS supermarket receipt" do
    assert OcrParser.parse(@etims_supermarket, today: @today) == %{
             vendor: "Naivas Limited",
             date: ~D[2026-09-21],
             amount_cents: 245_000,
             seller_pin: "P051234567X",
             invoice_number: "KRACU0100012345/1234"
           }
  end

  test "a strong label beats an earlier plain TOTAL, and the buyer PIN is skipped" do
    text = """
    JAVA HOUSE
    Buyer PIN: A123456789B
    Seller PIN: P000111222Z
    SUBTOTAL  1,000.00
    TOTAL ITEMS  4
    GRAND TOTAL  KES 1,160.00
    Served on 5 Sep 2026
    """

    assert %{
             amount_cents: 116_000,
             seller_pin: "P000111222Z",
             date: ~D[2026-09-05],
             vendor: "Java House"
           } =
             OcrParser.parse(text, today: @today)
  end

  test "the amount can sit on the line after its label" do
    text = "SHOP\nAMOUNT DUE\n1 250.50\n"
    assert %{amount_cents: 125_050} = OcrParser.parse(text, today: @today)
  end

  test "accepts ISO, two-digit-year and month-name dates" do
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nDATE 2026-08-30", today: @today)
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nDate: 30.08.26", today: @today)
    assert %{date: ~D[2026-08-30]} = OcrParser.parse("X\nAug 30, 2026", today: @today)
  end

  test "ignores impossible and future dates" do
    assert %{date: nil} = OcrParser.parse("X\nDATE 31/02/2026", today: @today)
    assert %{date: nil} = OcrParser.parse("X\nDATE 01/01/2030", today: @today)
  end

  test "skips header lines that are not the business name" do
    text = """
    WELCOME
    ***
    TEL 0722 000 000
    Mama Oliech Restaurant
    """

    assert %{vendor: "Mama Oliech Restaurant"} = OcrParser.parse(text, today: @today)
  end

  test "keeps short all-caps words like KFC as they are" do
    assert %{vendor: "KFC Junction Mall"} = OcrParser.parse("KFC JUNCTION MALL", today: @today)
  end

  test "text with nothing recognisable gives all nils" do
    assert OcrParser.parse("", today: @today) == %{
             vendor: nil,
             date: nil,
             amount_cents: nil,
             seller_pin: nil,
             invoice_number: nil
           }
  end
end
