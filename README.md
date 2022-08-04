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

**Note:** If you override the base currency, or your curreny of MoneyMoney differs from the CapTrader account, then you may want to create a custom Flex-Query, where you enable conversion rates. Ensure you add `account information`, `cash reports` and `open positions` to your custom Flex-Query.
If you do not enable conversion rates, then this plugin fetches conversion rates when needed, but they may differ from those of your Flex-Queries.
