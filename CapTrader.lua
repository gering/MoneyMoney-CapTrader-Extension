-- MIT License
-- Copyright (c) 2022 Robert Gering
-- https://github.com/gering/MoneyMoney-CapTrader-Extension

WebBanking {
  version = 1.0,
  country = "de",
  services = { "CapTrader", "IBKR" },
  description = string.format(MM.localizeText("Get portfolio for %s"), "CapTrader")
}

-- State
local token
local queryId
local reference
local cachedContent
local baseCurrency

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "CapTrader" or bankCode == "IBKR")
end

function InitializeSession(protocol, bankCode, username, customer, password)
  queryId = username
  token = password
  cachedContent = nil

  MM.printStatus("Requesting FlexQuery Reference…")

  -- Create HTTPS connection object.
  print("Requesting FlexQuery Reference")
  local url = "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.SendRequest?t=" .. token .. "&q= " .. queryId .. "&v=3"
  local headers = { Accept = "application/xml" }
  local connection = Connection()
  local content = connection:request("GET", url, nil, nil, headers)

  -- Extract status and reference code
  local status = content:match("Status>(.-)<")
  print("Status: " .. status)

  reference = content:match("ReferenceCode>(.-)<")
  print("Reference: " .. reference)

  if status ~= "Success" then
    return LoginFailed
  end 
end

function ListAccounts(knownAccounts)
  local statement = getStatement()

  -- Parse account info
  local accountInfo = statement:match("<AccountInformation(.-)/>")
  local owner = accountInfo:match("name=\"(.-)\"")
  local accountNumber = accountInfo:match("accountId=\"(.-)\"")
  local currency = accountInfo:match("currency=\"(.-)\"")

  local portfolio = {
    name = "CapTrader " .. MM.localizeText("Portfolio") ,
    owner = owner,
    accountNumber = accountNumber,
    currency = currency,
    portfolio = true,
    type = AccountTypePortfolio
  }

  local account = {
    name = "CapTrader " .. MM.localizeText("Account"),
    owner = owner,
    accountNumber = accountNumber,
    currency = currency,
    portfolio = false,
    type = AccountTypeSavings
  }

  return {portfolio, account}
end

function RefreshAccount(account, since)
  if account.portfolio == true then
    return RefreshAccountPortfolio()
  else
    return RefreshAccountBalance()
  end
end

function RefreshAccountPortfolio()
  local statement = getStatement()
  local openPositions = statement:match("<OpenPositions(.-)</OpenPositions>")
  local mySecurities = {}

  -- parse open positions
  for openPosition in openPositions:gmatch("<OpenPosition.-/>") do
    print("parsing open position: " .. openPosition)

    local symbol = openPosition:match("symbol=\"(.-)\"")
    local isin = openPosition:match("isin=\"(.-)\"")
    local exchange = openPosition:match("listingExchange=\"(.-)\"")
    local quantity = tonumber(openPosition:match("position=\"(.-)\""))
    local costBasisMoney = tonumber(openPosition:match("costBasisMoney=\"(.-)\""))
    local currency = openPosition:match("currency=\"(.-)\"")
    local price = tonumber(openPosition:match("markPrice=\"(.-)\""))
    local fxRate = tonumber(openPosition:match("fxRateToBase=\"(.-)\""))

    if quantity > 0 then
      local s = {
        name = symbol, -- Bezeichnung des Wertpapiers
        isin = isin, -- ISIN
        market = exchange, -- Börse
        quantity = quantity, -- Nominalbetrag oder Stückzahl
        currency = nil, -- Währung bei Nominalbetrag oder nil bei Stückzahl
        amount = price * quantity * fxRate, -- Wert der Depotposition in Kontowährung
        originalCurrencyAmount = price * quantity, -- Wert der Depotposition in Originalwährung
        currencyOfOriginalAmount = currency, -- Originalwährung
        price = price, -- Aktueller Preis oder Kurs
        currencyOfPrice = currency, -- Von der Kontowährung abweichende Währung des Preises
        purchasePrice = costBasisMoney / quantity, -- Kaufpreis oder Kaufkurs
        currencyOfPurchasePrice = currency, -- Von der Kontowährung abweichende Währung des Kaufpreises
        exchangeRate = fxRate -- Wechselkurs zum Kaufzeitpunkt
      }

      dump(s)
      mySecurities[#mySecurities+1] = s
    end
  end

  local result = {securities = mySecurities}
  dump(result)
  return result
end

-- TODO -> display in balances
function RefreshAccountBalance()
  local statement = getStatement()
  local cashReports = statement:match("<CashReport(.-)</CashReport>")
  local myBalances = {}
  local myBalance = 0

  -- parse cash reports
  for cashReport in cashReports:gmatch("<CashReportCurrency.-/>") do
    print("parsing cash report: " .. cashReport)

    local cash = tonumber(cashReports:match("endingSettledCash=\"(.-)\""))
    local currency = cashReports:match("currency=\"(.-)\"")

    if currency == "BASE_SUMMARY" then
      myBalance = cash
    else
      myBalances[#myBalances+1] = { cash, currency }
    end
  end

  local result = {balance = myBalance, balances = myBalances}
  dump(result)
  return result
end

function EndSession()
  -- nothing to do
end

-- Helper

function getStatement()
  if cachedContent == nil then
    -- Create HTTPS connection object.
    print("Requesting FlexQuery Statement")
    local url = "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token .. "&q= " .. reference .. "&v=3"
    local headers = { Accept = "application/xml" }
    local connection = Connection()
    cachedContent = connection:request("GET", url, nil, nil, headers)
  end

  return cachedContent
end
