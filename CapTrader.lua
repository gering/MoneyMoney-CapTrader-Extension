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

  if baseCurrencyOverride ~= nil and baseCurrencyOverride ~= baseCurrencyOriginal then
    print("Override base currency: " .. baseCurrencyOverride)
  end

  -- Parse rates if available
  parseConversionRates()

  local positions = parseAccountPositions(account)
  local balances = parseAccountBalances(account)
  return {securities = concat(balances, positions)}
end

function parseAccountPositions(account)
  local openPositions = getStatement():match("<OpenPositions(.-)</OpenPositions>")
  local mySecurities = {}

  -- Parse open positions
  for openPosition in openPositions:gmatch("<OpenPosition.-/>") do
    print("Parsing open position: " .. openPosition)

    local symbol = openPosition:match("symbol=\"(.-)\"")
    local isin = openPosition:match("isin=\"(.-)\"")
    local exchange = openPosition:match("listingExchange=\"(.-)\"")
    local quantity = tonumber(openPosition:match("position=\"(.-)\""))
    local costBasisMoney = tonumber(openPosition:match("costBasisMoney=\"(.-)\""))
    local currency = openPosition:match("currency=\"(.-)\"")
    local price = tonumber(openPosition:match("markPrice=\"(.-)\""))
    
    -- update cache
    setFxRate(baseCurrencyOriginal, currency, 1/tonumber(openPosition:match("fxRateToBase=\"(.-)\""))) 

    if quantity > 0 then
      mySecurities[#mySecurities+1] = {
        name = symbol, -- Bezeichnung des Wertpapiers
        isin = isin, -- ISIN
        market = exchange, -- Börse
        quantity = quantity, -- Nominalbetrag oder Stückzahl
        currency = nil, -- Währung bei Nominalbetrag oder nil bei Stückzahl
        amount = convertToBase(price * quantity, currency), -- Wert der Depotposition in Kontowährung
        originalCurrencyAmount = price * quantity, -- Wert der Depotposition in Originalwährung
        currencyOfOriginalAmount = currency, -- Originalwährung
        price = price, -- Aktueller Preis oder Kurs
        currencyOfPrice = currency, -- Von der Kontowährung abweichende Währung des Preises
        purchasePrice = costBasisMoney / quantity, -- Kaufpreis oder Kaufkurs
        currencyOfPurchasePrice = currency, -- Von der Kontowährung abweichende Währung des Kaufpreises
        exchangeRate = getFxRateToBase(currency) -- Wechselkurs zum Kaufzeitpunkt
      }
    end
  end

  return mySecurities
end

function parseAccountBalances(account)
  local cashReports = getStatement():match("<CashReport(.-)</CashReport>")
  local myBalances = {}
  local hasForexPositions = false

  -- Parse cash reports
  for cashReport in cashReports:gmatch("<CashReportCurrency.-/>") do
    print("Parsing cash report: " .. cashReport)

    local cash = tonumber(cashReport:match("endingSettledCash=\"(.-)\""))
    local currency = cashReport:match("currency=\"(.-)\"")

    if currency == "BASE_SUMMARY" then
      myBalances[#myBalances+1] = { 
        name = MM.localizeText("Settled Cash") .. " (" .. baseCurrencyOriginal .. ")",
        currency = baseCurrencyOriginal,
        quantity = cash,
        amount = convertToBase(cash, baseCurrencyOriginal),
        exchangeRate = getFxRateToBase(baseCurrencyOriginal)
      }    
    else
      if currency == account.currency then
        myBalances[#myBalances+1] = { 
          name = currency,
          currency = currency,
          amount = convertToBase(cash, currency)
        }
      else
        -- Other cash positions (not in base currency) do exist
        hasForexPositions = true
  
        myBalances[#myBalances+1] = { 
          name = currency,
          market =  MM.localizeText("Forex"),
          quantity = cash, 
          currency = currency,
          amount = convertToBase(cash, currency),
          exchangeRate = getFxRateToBase(currency)
        }
      end
    end
  end

  -- If other currencies are present, remove the amout for the base currency
  if hasForexPositions == true then
    myBalances[1].amount = nil
  end

  return myBalances
end

function parseConversionRates()
  local rates = getStatement():match("<ConversionRates(.-)</ConversionRates>")
  if rates == nil then
    print("No conversion rates provided")
  else
    for rate in rates:gmatch("<ConversionRate.-/>") do
      local from = rate:match("fromCurrency=\"(.-)\"")
      local to = rate:match("toCurrency=\"(.-)\"")
      local rate = tonumber(rate:match("rate=\"(.-)\""))
  
      if from == baseCurrencyOriginal then
        setFxRate(from, to, rate)
      end
      if to == baseCurrencyOriginal then
        setFxRate(to, from, 1/rate)
      end
    end
  end
end

function EndSession()
end

-- Helper

function concat(t1,t2)
  for i=1,#t2 do
      t1[#t1+1] = t2[i]
  end
  return t1
end

function getStatement()
  if cachedStatement == nil then
    print("Fetching FlexQuery Statement")
    MM.sleep(1)
    local url = "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token .. "&q= " .. reference .. "&v=3"
    local headers = { Accept = "application/xml" }
    cachedStatement = Connection():request("GET", url, nil, nil, headers)
  end

  return cachedStatement
end

function fetchFxRate(base, quote)
  local url = "https://cdn.jsdelivr.net/gh/fawazahmed0/currency-api@1/latest/currencies/" .. base:lower() .. ".json"
  local headers = { Accept = "application/json" }
  local content = Connection():request("GET", url, nil, nil, headers)
  local json = JSON(content):dictionary()
  local rates = json[base:lower()]
  local rate = rates[quote:lower()]
  print("Fetched: " .. base .. "/" .. quote .. ": " .. rate)
  return rate
end

function getFxRate(base, quote)
  if base:lower() == quote:lower() then
    return 1
  end

  -- Use cached rate
  local pair = base:upper() .. "/" .. quote:upper()
  if cachedFxRates[pair] ~= nil then
    return cachedFxRates[pair]
  end

  -- Use cached rate of reversed pair
  local reversedPair = quote:upper() .. "/" .. base:upper()
  if cachedFxRates[reversedPair] ~= nil then
    return 1/cachedFxRates[reversedPair]
  end

  -- Fetch rate
  local rate = fetchFxRate(base, quote)
  setFxRate(base, quote, rate)
  return rate
end

function getFxRateToBase(currency)
  return getFxRate(baseCurrencyOverride or baseCurrencyOriginal, currency)
end

function convertToBase(amount, currency)
  if currency == (baseCurrencyOverride or baseCurrencyOriginal) then
    return amount
  else
    local base = amount / getFxRateToBase(currency)
    print("Convert: " .. amount .. " " .. currency .. " = " .. base .. " " .. (baseCurrencyOverride or baseCurrencyOriginal))
    return base
  end
end

function setFxRate(base, quote, rate)
  if base ~= quote then
    local pair = base:upper() .. "/" .. quote:upper()
    if cachedFxRates[pair] == nil then
      print(pair .. " = " .. rate)
      cachedFxRates[pair] = rate
    end
  end
end
