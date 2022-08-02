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
local baseCurrencyOriginal
local baseCurrencyOverride

-- Cache
local cachedStatement
local cachedFxRates = {} -- currency pair (e.g. EUR/USD) : rate

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "CapTrader" or bankCode == "IBKR")
end

function InitializeSession(protocol, bankCode, username, customer, password)
  baseCurrencyOverride = username:match("[a-zA-Z]+")
  queryId = username:match("[0-9]+")  
  token = password

  if baseCurrencyOverride ~= nil then
    print("Override base currency: " .. baseCurrencyOverride)
  end

  -- Create HTTPS connection object.
  print("Requesting FlexQuery Reference")
  local url = "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.SendRequest?t=" .. token .. "&q= " .. queryId .. "&v=3"
  local headers = { Accept = "application/xml" }
  local content = Connection():request("GET", url, nil, nil, headers)

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
  -- Parse account info
  local accountInfo = getStatement():match("<AccountInformation(.-)/>")
  baseCurrencyOriginal = accountInfo:match("currency=\"(.-)\"")
  print("Account base currency: " .. baseCurrencyOriginal)

  local account = {
    name = "CapTrader " .. MM.localizeText("Portfolio"),
    owner = accountInfo:match("name=\"(.-)\""),
    accountNumber = accountInfo:match("accountId=\"(.-)\""),
    currency = baseCurrencyOverride or baseCurrencyOriginal,    
    portfolio = true,
    type = AccountTypePortfolio
  }

  return {account}
end

function RefreshAccount(account, since)
  -- Parse account info
  local accountInfo = getStatement():match("<AccountInformation(.-)/>")
  baseCurrencyOriginal = accountInfo:match("currency=\"(.-)\"")
  print("Account base currency: " .. baseCurrencyOriginal)

  local positions = FetchAccountPositions(account)
  local balances = FetchAccountBalances(account)
  return {securities = concat(balances, positions)}
end

function FetchAccountPositions(account)
  local openPositions = getStatement():match("<OpenPositions(.-)</OpenPositions>")
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
    
    -- update cache
    setFxRate(currency, baseCurrencyOriginal, tonumber(openPosition:match("fxRateToBase=\"(.-)\""))) 
    local fxRateToBase = getFxRateToBase(currency)
    local fxRate = 1 / fxRateToBase

    if quantity > 0 then
      mySecurities[#mySecurities+1] = {
        name = symbol, -- Bezeichnung des Wertpapiers
        isin = isin, -- ISIN
        market = exchange, -- Börse
        quantity = quantity, -- Nominalbetrag oder Stückzahl
        currency = nil, -- Währung bei Nominalbetrag oder nil bei Stückzahl
        amount = price * quantity * fxRateToBase, -- Wert der Depotposition in Kontowährung
        originalCurrencyAmount = price * quantity, -- Wert der Depotposition in Originalwährung
        currencyOfOriginalAmount = currency, -- Originalwährung
        price = price, -- Aktueller Preis oder Kurs
        currencyOfPrice = currency, -- Von der Kontowährung abweichende Währung des Preises
        purchasePrice = costBasisMoney / quantity, -- Kaufpreis oder Kaufkurs
        currencyOfPurchasePrice = currency, -- Von der Kontowährung abweichende Währung des Kaufpreises
        exchangeRate = fxRate -- Wechselkurs zum Kaufzeitpunkt
      }
    end
  end

  return mySecurities
end

function FetchAccountBalances(account)
  local cashReports = getStatement():match("<CashReport(.-)</CashReport>")
  local myBalances = {}
  local hasForexPositions = false

  -- parse cash reports
  for cashReport in cashReports:gmatch("<CashReportCurrency.-/>") do
    print("parsing cash report: " .. cashReport)

    local cash = tonumber(cashReport:match("endingSettledCash=\"(.-)\""))
    local currency = cashReport:match("currency=\"(.-)\"")

    if currency == "BASE_SUMMARY" then
      myBalances[#myBalances+1] = { 
        name = MM.localizeText("Settled Cash") .. " (" .. account.currency .. ")",
        currency = account.currency,
        quantity = cash * getFxRateToBase(baseCurrencyOriginal)
      }    
    else
      if currency == account.currency then
        myBalances[#myBalances+1] = { 
          name = currency,
          currency = currency,
          amount = cash * getFxRateToBase(currency)
        }
      else
        -- other cash positions, not in base currency
        hasForexPositions = true
  
        myBalances[#myBalances+1] = { 
          name = currency,
          market =  MM.localizeText("Forex"),
          quantity = cash, 
          currency = currency,
          amount = cash * getFxRateToBase(currency)
        }
      end
    end
  end

  -- If no other currencies are present, add the amout to the base currency
  if hasForexPositions == false then
    myBalances[1].amount = myBalances[1].quantity
    myBalances[1].quantity = nil
  end

  return myBalances
end

function EndSession()
  -- nothing to do
end

-- Helper

function getStatement()
  if cachedStatement == nil then
    print("Fetching FlexQuery Statement")
    local url = "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token .. "&q= " .. reference .. "&v=3"
    local headers = { Accept = "application/xml" }
    cachedStatement = Connection():request("GET", url, nil, nil, headers)
  end

  return cachedStatement
end

function concat(t1,t2)
  for i=1,#t2 do
      t1[#t1+1] = t2[i]
  end
  return t1
end

function fetchFxRate(base, quote)
  print("Fetching FX rates: " .. base)
  local url = "https://cdn.jsdelivr.net/gh/fawazahmed0/currency-api@1/latest/currencies/" .. base:lower() .. ".json"
  local headers = { Accept = "application/json" }
  local content = Connection():request("GET", url, nil, nil, headers)
  local json = JSON(content):dictionary()
  local rates = json[base:lower()]
  return rates[quote:lower()]
end

function getFxRate(base, quote)
  if base:lower() == quote:lower() then
    return 1
  end

  local pair = base:upper() .. "/" .. quote:upper()

  if cachedFxRates[pair] ~= nil then
    return cachedFxRates[pair]
  end

  local rate = fetchFxRate(base, quote)
  setFxRate(base, quote, rate)
  return rate
end

function getFxRateToBase(currency)
  return 1 / getFxRate(baseCurrencyOverride or baseCurrencyOriginal, currency)
end

function setFxRate(base, quote, rate)
  cachedFxRates[base:upper() .. "/" .. quote:upper()] = rate
  cachedFxRates[quote:upper() .. "/" .. base:upper()] = 1 / rate
end
