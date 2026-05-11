# MoneyMoney-CapTrader-Extension
Unofficial CapTrader Extension for MoneyMoney. Fetches balances from CapTrader and returns them as securities.

## Getting started

Enable Flex-Web-Service in your CapTrader account settings and generate a `Token`. This token will be your password.
Then a Flex-Query-ID is needed as username. You could simply configure third party services and enable **Yodlee**. Use the `Query-ID` from **Yodlee** as username.

Provide this to MoneyMoney:
- Username: `Query-ID` e.g. 0123456
- Password: `Token` e.g. 123456789012345678

## Setting base currency

This Plugin uses EUR as default base currency. This means MoneyMoney will display in EUR, even if your CapTrader account is set to USD. But, in the case your CapTrader account uses a different base currency like USD and you want to display your securities in USD as well, you should override the base currency. Simply append the currency to the `Query-ID` like so:

- Username: `Query-ID/Currency` e.g. 0123456/USD
- Password: `Token` e.g. 123456789012345678

## Required Flex-Query sections

If you create a custom Flex-Query (instead of using **Yodlee**), it must include the following sections, otherwise MoneyMoney will fail to load your portfolio:

- **Account Information** (required)
- **Open Positions** (required)
- **Cash Report** (required)
- **Conversion Rates** (optional — see below)

You can find these settings in CapTrader → Reports → Flex Queries → your query → **Sections**.

## Base currency conversion

If you override the base currency, or the currency of MoneyMoney differs from the CapTrader account, then you may want to enable **Conversion Rates** in your custom Flex-Query. Without it the plugin fetches FX rates from the ECB when needed, but those may differ slightly from CapTrader's.
