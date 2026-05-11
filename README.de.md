<!-- Diese Datei bei Änderungen mit README.md synchron halten. -->
[Lesen Sie dies auf Englisch](README.md)

# MoneyMoney-CapTrader-Erweiterung
Inoffizielle CapTrader-Erweiterung für MoneyMoney. Ruft Salden von CapTrader ab und gibt sie als Wertpapiere zurück.

## Einrichtung

Aktivieren Sie den Flex-Web-Service in den Einstellungen Ihres CapTrader-Kontos und erzeugen Sie einen `Token`. Dieser Token ist Ihr Passwort.
Zusätzlich wird eine Flex-Query-ID als Benutzername benötigt. Am einfachsten konfigurieren Sie die Drittanbieterdienste und aktivieren **Yodlee**. Verwenden Sie dann die `Query-ID` von **Yodlee** als Benutzernamen.

In MoneyMoney eintragen:
- Benutzername: `Query-ID`, z. B. 0123456
- Passwort: `Token`, z. B. 123456789012345678

## Basiswährung festlegen

Standardmäßig verwendet diese Erweiterung EUR als Basiswährung. MoneyMoney zeigt also in EUR an, auch wenn Ihr CapTrader-Konto auf USD eingestellt ist. Falls Ihr CapTrader-Konto eine andere Basiswährung wie USD verwendet und Sie Ihre Wertpapiere ebenfalls in USD anzeigen möchten, können Sie die Basiswährung überschreiben. Hängen Sie dazu einfach die Währung an die `Query-ID` an:

- Benutzername: `Query-ID/Währung`, z. B. 0123456/USD
- Passwort: `Token`, z. B. 123456789012345678

## Erforderliche Flex-Query-Sections

Wenn Sie eine eigene Flex-Query erstellen (statt **Yodlee** zu verwenden), müssen darin folgende Sections enthalten sein, sonst kann MoneyMoney Ihr Depot nicht laden:

- **Account Information** (erforderlich)
- **Open Positions** (erforderlich)
- **Cash Report** (erforderlich)
- **Conversion Rates** (optional — siehe unten)

Sie finden diese Einstellungen in CapTrader unter Reports → Flex Queries → Ihre Query → **Sections**.

## Währungsumrechnung

Wenn Sie die Basiswährung überschreiben oder die Währung in MoneyMoney von der des CapTrader-Kontos abweicht, sollten Sie in Ihrer eigenen Flex-Query **Conversion Rates** aktivieren. Ohne diese Section bezieht die Erweiterung die Wechselkurse bei Bedarf von der EZB; diese können geringfügig von den CapTrader-Kursen abweichen.
