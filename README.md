# MoneyMoney-CapTrader-Extension
Unofficial CapTrader Extension for MoneyMoney. Fetches balances from CapTrader and returns them as securities.

## Getting started

Enable Flex-Web-Service in your CapTrader account settings and generate a `Token`. This will be your password.
Then configure third party services and enable **Yodlee**. Use the `Query-ID` from **Yodlee** as username.

Provide this to MoneyMoney:
- Username: `Query-ID`
- Password: `Token`

## Setting base currency

If you like to override the base currency of your CapTrader account, you could simply add a new base currency by appending it to the `Query-ID` like so:

- Username: `Query-ID/BaseCurrency`
- Password: `Token`

If your account uses USD as base currency and you like to display in EUR, then add `"/EUR"` at the end of the Query-ID
- e.g. `0123456/EUR`

Note: If you override the base currency, you may want to create a custom Flex-Query, where you enable conversion rates. Ensure you add `account information`, `cash reports` and `open positions` to your custom Flex-Query.
