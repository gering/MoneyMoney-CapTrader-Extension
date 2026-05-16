-- MIT License
-- Copyright (c) 2023 Robert Gering
-- https://github.com/gering/MoneyMoney-CapTrader-Extension

WebBanking {
  version = 1.3,
  country = "de",
  services = { "CapTrader", "IBKR" },
  description = string.format(MM.localizeText("Get portfolio for %s"), "CapTrader")
}

-- State
local token
local queryId
local reference
local baseCurrencyOriginal
local baseCurrencyOverride -- default is EUR

-- Cache
local cachedStatement
local cachedFxRates = {} -- currency pair (e.g. EUR/USD) : rate

-- Persistent reference cache. IBKR's per-(query, token) cooldown after
-- SendRequest can last many hours; reusing a still-valid reference avoids
-- tripping ErrorCode 1001. The 1017 handler in getStatement() invalidates
-- early if IBKR drops the reference before the local TTL.
local referenceTtl = 12 * 3600 -- 12h, covers a typical workday

function tokenFingerprint()
  return MM.sha256(token):sub(1, 16)
end

function loadCachedReference()
  local ref       = LocalStorage["ref_"          .. queryId]
  local expiresAt = LocalStorage["refExpiresAt_" .. queryId]
  local tokenFp   = LocalStorage["refTokenFp_"   .. queryId]
  if ref and tokenFp == tokenFingerprint() and expiresAt and os.time() < expiresAt then
    print("Reusing cached FlexQuery reference (expires in " .. (expiresAt - os.time()) .. "s)")
    return ref
  end
  return nil
end

function storeReference(ref)
  LocalStorage["ref_"          .. queryId] = ref
  LocalStorage["refExpiresAt_" .. queryId] = os.time() + referenceTtl
  LocalStorage["refTokenFp_"   .. queryId] = tokenFingerprint()
end

function invalidateReference()
  LocalStorage["ref_"          .. queryId] = nil
  LocalStorage["refExpiresAt_" .. queryId] = nil
  LocalStorage["refTokenFp_"   .. queryId] = nil
end

-- Extensions

string.parseTagContent = function(s, tag)
  return s:match("<" .. tag .. ".->(.-)</" .. tag .. ">")
end

string.parseTag = function(s, tag)
  return s:match("<" .. tag .. ".-/>")
end

string.parseTags = function(s, tag)
  return s:gmatch("<" .. tag .. ".-/>")
end

string.parseArgs = function(s)
  local args = {}
  s:gsub("([%-%w]+)=([\"'])(.-)%2", function(w, _, a)
      args[w] = a
  end)
  return args
end

-- Plugin

function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and (bankCode == "CapTrader" or bankCode == "IBKR")
end

function InitializeSession(protocol, bankCode, username, customer, password)
  baseCurrencyOverride = username:match("[a-zA-Z]+") or "EUR"
  queryId = username:match("[0-9]+")
  token = password

  reference = loadCachedReference()
  if reference then return end

  local maxAttempts = 3
  for attempt = 1, maxAttempts do
    print("Requesting FlexQuery Reference (attempt " .. attempt .. "/" .. maxAttempts .. ")")
    local content = Connection():request("GET", "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.SendRequest?t=" .. token .. "&q=" .. queryId .. "&v=3")

    local status = content:parseTagContent("Status")
    print("Status: " .. (status or "?"))

    if status == "Success" then
      reference = content:parseTagContent("ReferenceCode")
      if reference == nil or reference == "" then
        error("FlexQuery returned Success without a ReferenceCode")
      end
      print("Reference: " .. reference)
      storeReference(reference)
      return
    end

    local errorCode = content:parseTagContent("ErrorCode")
    local errorMessage = content:parseTagContent("ErrorMessage")
    print("ErrorCode: " .. (errorCode or "?") .. " - " .. (errorMessage or ""))

    -- Only 1001 is transient; all other error codes are permanent.
    if errorCode ~= "1001" or attempt == maxAttempts then
      error(errorMessage or ("FlexQuery SendRequest failed (ErrorCode " .. (errorCode or "unknown") .. ")"))
    end

    local delay = attempt * 5
    print("Retrying in " .. delay .. "s")
    MM.sleep(delay)
  end
end

function ListAccounts(knownAccounts)
  local account = parseAccountInfo()
  return {account}
end

function RefreshAccount(account, since)
  parseAccountInfo() -- Load baseCurrencyOriginal
  parseConversionRates() -- Parse rates if available

  local positions = parseAccountPositions(account)
  local balances = parseAccountBalances(account)
  return {securities = concat(balances, positions)}
end

function EndSession()
end

-- Parsing FlexQuery

function getStatement()
  if cachedStatement ~= nil then
    return cachedStatement
  end

  -- 1019 = statement still generating; poll until ready.
  local maxAttempts = 10
  for attempt = 1, maxAttempts do
    print("Fetching FlexQuery Statement (attempt " .. attempt .. "/" .. maxAttempts .. ")")
    local content = Connection():request("GET", "https://ndcdyn.interactivebrokers.com/Universal/servlet/FlexStatementService.GetStatement?t=" .. token .. "&q=" .. reference .. "&v=3")

    -- A successful statement is wrapped in <FlexQueryResponse>; errors and
    -- progress notifications come back as <FlexStatementResponse>.
    if type(content) == "string" and content:find("<FlexQueryResponse", 1, true) then
      cachedStatement = content
      return cachedStatement
    end

    local errorCode = content:parseTagContent("ErrorCode")
    local errorMessage = content:parseTagContent("ErrorMessage")
    print("ErrorCode: " .. (errorCode or "?") .. " - " .. (errorMessage or ""))

    -- 1017 = reference invalid (IBKR TTL shorter than ours). Drop the cache.
    if errorCode == "1017" then
      invalidateReference()
    end

    if errorCode ~= "1019" or attempt == maxAttempts then
      error(errorMessage or ("FlexQuery GetStatement failed (ErrorCode " .. (errorCode or "unknown") .. ")"))
    end

    MM.sleep(2)
  end
end

function missingSectionError(sectionLabel)
  error(string.format(
    MM.localizeText("FlexQuery section '%s' is missing. Please enable it in the CapTrader FlexQuery configuration."),
    sectionLabel))
end

function parseAccountInfo()
  local tag = getStatement():parseTag("AccountInformation")
  if tag == nil then missingSectionError("Account Information") end
  local accountInfo = tag:parseArgs()
  baseCurrencyOriginal = accountInfo.currency

  print("Account base currency: " .. baseCurrencyOriginal)
  if baseCurrencyOverride ~= nil and baseCurrencyOverride ~= baseCurrencyOriginal then
    print("Override base currency: " .. baseCurrencyOverride)
  end

  local account = {
    name = "CapTrader " .. MM.localizeText("Portfolio"),
    owner = accountInfo.name,
    accountNumber = accountInfo.accountId,
    currency = baseCurrencyOverride or baseCurrencyOriginal,
    portfolio = true,
    type = AccountTypePortfolio
  }

  return account
end

function parseAccountPositions(account)
  local openPositions = getStatement():parseTagContent("OpenPositions")
  if openPositions == nil then missingSectionError("Open Positions") end
  local mySecurities = {}

  -- Parse open positions
  for openPosition in openPositions:parseTags("OpenPosition") do
    print("Parsing open position: " .. openPosition)

    local pos = openPosition:parseArgs()
    local quantity = pos.position * pos.multiplier

    -- Update cache
    setFxRate(baseCurrencyOriginal, pos.currency, 1/pos.fxRateToBase)

    mySecurities[#mySecurities+1] = {
      name = pos.symbol,
      isin = pos.isin,
      market = pos.listingExchange,
      quantity = quantity,
      originalCurrencyAmount = pos.markPrice * quantity,
      currencyOfOriginalAmount = pos.currency,
      price = pos.markPrice,
      currencyOfPrice = pos.currency,
      purchasePrice = pos.costBasisMoney / pos.position,
      currencyOfPurchasePrice = pos.currency,
      exchangeRate = getFxRateToBase(pos.currency),
      amount = convertToBase(pos.markPrice * quantity, pos.currency)
    }
  end

  return mySecurities
end

function parseAccountBalances(account)
  local cashReports = getStatement():parseTagContent("CashReport")
  if cashReports == nil then missingSectionError("Cash Report") end
  local myBalances = {}
  local hasForexPositions = false

  -- Parse cash reports
  for cashReport in cashReports:parseTags("CashReportCurrency") do
    print("Parsing cash report: " .. cashReport)

    local report = cashReport:parseArgs()
    local cash = report.endingSettledCash
    local currency = report.currency

    if currency == "BASE_SUMMARY" then
      myBalances[#myBalances+1] = {
        name = "> " .. MM.localizeText("Settled Cash") .. " (" .. baseCurrencyOriginal .. ")",
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
    myBalances[1].amount = 0
  end

  return myBalances
end

function parseConversionRates()
  local rates = getStatement():parseTagContent("ConversionRates")
  if rates == nil then
    print("No conversion rates provided")
  else
    for conversionRate in rates:parseTags("ConversionRate") do
      local conversion = conversionRate:parseArgs()

      if conversion.fromCurrency == baseCurrencyOriginal then
        setFxRate(conversion.fromCurrency, conversion.toCurrency, conversion.rate)
      end
      if conversion.toCurrency == baseCurrencyOriginal then
        setFxRate(conversion.toCurrency, conversion.fromCurrency, 1/conversion.rate)
      end
    end
  end
end

-- Helper

function concat(t1,t2)
  for i=1,#t2 do
      t1[#t1+1] = t2[i]
  end
  return t1
end

function fetchFxRate(base, quote)
  if quote == "EUR" then
    return 1 / fetchFxRate(quote, base)
  end

  if base == "EUR" then
    local content = Connection():request("GET", "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")
    for cube in content:parseTags("Cube") do
      local conversion = cube:parseArgs()
      if conversion.currency == quote then
        print("Fetched: " .. base .. "/" .. quote .. " @ " .. conversion.rate)
        return conversion.rate
      end
    end
  end

  print("Couldn't fetch FX rate for " .. base .. "/" .. quote)
  return nil
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

  -- Fetch rate as fallback
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

