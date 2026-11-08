# Huawei LTE CPE B2368-66 auto reboot
# Flow: authToken login -> skip change-password -> POST isReset=1
#
# Usage:
#   1. Copy config.example.json to config.json and fill credentials
#   2. Double-click Reboot-Router.bat
#   OR: powershell -ExecutionPolicy Bypass -File .\huawei-b2368-reboot.ps1 -Auto -WaitOnline

param(
    [string]$RouterUrl = "",
    [string]$Username = "",
    [string]$Password = "",
    [switch]$Auto,
    [switch]$WaitOnline
)

$ErrorActionPreference = "Stop"
$cookieJar = Join-Path $env:TEMP "huawei_b2368_cookies.txt"
$loginPage = Join-Path $env:TEMP "huawei_login_page.html"
$loginOut = Join-Path $env:TEMP "huawei_login.html"
$rebootOut = Join-Path $env:TEMP "huawei_reboot.html"
$bodyFile = Join-Path $env:TEMP "huawei_post_body.txt"
$debugDir = Join-Path $PSScriptRoot "huawei-reboot-debug"
$configPath = Join-Path $PSScriptRoot "config.json"
$curlCommon = @("-k", "-s", "--ssl-no-revoke", "--http1.0", "--max-time", "25")

function Assert-Curl {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "curl.exe not found. Install curl or use Windows 10+."
    }
}

function Get-Base64Password([string]$Plain) {
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Plain))
}

function Save-DebugCopy([string]$Source, [string]$Name) {
    if (-not (Test-Path $Source)) { return }
    New-Item -ItemType Directory -Force -Path $debugDir | Out-Null
    Copy-Item $Source (Join-Path $debugDir $Name) -Force
}

function Get-HiddenValue([string]$Html, [string]$Name) {
    $pattern = ('(?is)name=["'']{0}["''][^>]*value=["'']([^"'']*)["'']|value=["'']([^"'']*)["''][^>]*name=["'']{0}["'']' -f [regex]::Escape($Name))
    $m = [regex]::Match($Html, $pattern)
    if (-not $m.Success) { return "" }
    if ($m.Groups[1].Success -and $m.Groups[1].Value) { return $m.Groups[1].Value }
    return $m.Groups[2].Value
}

function Write-FormBody([hashtable]$Fields, [string]$Path) {
    $parts = foreach ($k in $Fields.Keys) {
        "{0}={1}" -f [uri]::EscapeDataString([string]$k), [uri]::EscapeDataString([string]$Fields[$k])
    }
    [IO.File]::WriteAllText($Path, ($parts -join "&"))
}

function Clear-Secrets {
    Remove-Item $cookieJar, $bodyFile -ErrorAction SilentlyContinue
}

function Read-LocalConfig {
    if (-not (Test-Path $configPath)) { return $null }
    return Get-Content $configPath -Raw | ConvertFrom-Json
}

# Load config.json / env (never hardcode secrets in the public script)
$cfg = Read-LocalConfig
if (-not $RouterUrl) {
    if ($cfg -and $cfg.routerUrl) { $RouterUrl = [string]$cfg.routerUrl }
    elseif ($env:HUAWEI_ROUTER_URL) { $RouterUrl = $env:HUAWEI_ROUTER_URL }
    else { $RouterUrl = "https://192.168.1.1" }
}
if (-not $Username) {
    if ($cfg -and $cfg.username) { $Username = [string]$cfg.username }
    elseif ($env:HUAWEI_ROUTER_USER) { $Username = $env:HUAWEI_ROUTER_USER }
    else { $Username = "user" }
}
if (-not $Password) {
    if ($cfg -and $cfg.password) { $Password = [string]$cfg.password }
    elseif ($env:HUAWEI_ROUTER_PASS) { $Password = $env:HUAWEI_ROUTER_PASS }
}

$RouterUrl = $RouterUrl.TrimEnd("/")

Write-Host ""
Write-Host "=== Huawei B2368-66 Reboot ===" -ForegroundColor Cyan
Write-Host "Router: $RouterUrl"
Write-Host ""

Assert-Curl
Clear-Secrets
Remove-Item $loginPage, $loginOut, $rebootOut -ErrorAction SilentlyContinue

if (-not $Auto) {
    $enteredUser = Read-Host "Username [$Username]"
    if (-not [string]::IsNullOrWhiteSpace($enteredUser)) {
        $Username = $enteredUser.Trim()
    }
    $securePass = Read-Host "Password (Enter = config/env value)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
    try {
        $typed = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if (-not [string]::IsNullOrEmpty($typed)) {
        $Password = $typed
    }
}

if ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password)) {
    throw "Username/password missing. Create config.json from config.example.json (or set env vars)."
}

Write-Host "[1/4] Fetching login page / authToken..." -ForegroundColor Yellow
$null = & curl.exe @curlCommon -c $cookieJar -b $cookieJar -A "Mozilla/5.0" -o $loginPage "$RouterUrl/login.cgi"
Save-DebugCopy $loginPage "00-login-page.html"
if (-not (Test-Path $loginPage) -or (Get-Item $loginPage).Length -lt 100) {
    throw "Could not load login page. Connect to this router's Wi-Fi/LAN and retry."
}

$loginHtml = Get-Content $loginPage -Raw
$authToken = Get-HiddenValue $loginHtml "authToken"
if ([string]::IsNullOrWhiteSpace($authToken)) {
    throw "authToken missing on login page. Router firmware may differ."
}

$hiddenPassword = Get-Base64Password $Password
$Password = $null

$fields = [ordered]@{
    authToken        = $authToken
    mtenCurrent_Min  = (Get-HiddenValue $loginHtml "mtenCurrent_Min")
    mtenCurrent_Sec  = (Get-HiddenValue $loginHtml "mtenCurrent_Sec")
    accountLock      = (Get-HiddenValue $loginHtml "accountLock")
    languageChange   = "0"
    languageSelected = "ENG"
    Multilingual     = "0"
    UserName         = $Username
    password         = ""
    hiddenPassword   = $hiddenPassword
    submitValue      = "1"
}
Write-FormBody $fields $bodyFile
$hiddenPassword = $null
$authToken = $null

Write-Host "[2/4] Logging in as '$Username'..." -ForegroundColor Yellow
$loginCode = & curl.exe @curlCommon `
    -c $cookieJar -b $cookieJar `
    -A "Mozilla/5.0" `
    -H "Referer: $RouterUrl/login.cgi" `
    -H "Origin: $RouterUrl" `
    -H "Content-Type: application/x-www-form-urlencoded" `
    --data-binary "@$bodyFile" `
    -o $loginOut `
    -w "%{http_code}" `
    "$RouterUrl/login.cgi"

Remove-Item $bodyFile -ErrorAction SilentlyContinue
Save-DebugCopy $loginOut "01-login.html"

$loginResult = if (Test-Path $loginOut) { Get-Content $loginOut -Raw } else { "" }
if ($loginResult -match "(?i)incorrect|invalid password|wrong password|three times") {
    Clear-Secrets
    throw "Login failed. Check username/password."
}

# Skip must POST submitValue=0 (+ authToken). Plain GET is not enough.
if ($loginResult -match "(?i)Change Password|setup a new password|modify your password|passWarning") {
    Write-Host "      Change Password prompt -> Skip (POST submitValue=0)..." -ForegroundColor DarkYellow
    $skipToken = Get-HiddenValue $loginResult "authToken"
    Write-FormBody ([ordered]@{
        authToken   = $skipToken
        submitValue = "0"
    }) $bodyFile
    $null = & curl.exe @curlCommon `
        -c $cookieJar -b $cookieJar `
        -A "Mozilla/5.0" `
        -H "Referer: $RouterUrl/login.cgi" `
        -H "Content-Type: application/x-www-form-urlencoded" `
        --data-binary "@$bodyFile" `
        -o (Join-Path $env:TEMP "huawei_main.html") `
        "$RouterUrl/indexMain.cgi"
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
else {
    $null = & curl.exe @curlCommon `
        -c $cookieJar -b $cookieJar `
        -A "Mozilla/5.0" `
        -H "Referer: $RouterUrl/login.cgi" `
        -o (Join-Path $env:TEMP "huawei_main.html") `
        "$RouterUrl/indexMain.cgi"
}
Save-DebugCopy (Join-Path $env:TEMP "huawei_main.html") "02-main.html"

Write-Host "[3/4] Opening Reboot page..." -ForegroundColor Yellow
$null = & curl.exe @curlCommon `
    -c $cookieJar -b $cookieJar `
    -A "Mozilla/5.0" `
    -H "Referer: $RouterUrl/indexMain.cgi" `
    -o $rebootOut `
    -w "%{http_code}" `
    "$RouterUrl/reboot.cgi"
Save-DebugCopy $rebootOut "03-reboot-page.html"
$rebootHtml = if (Test-Path $rebootOut) { Get-Content $rebootOut -Raw } else { "" }

if ($rebootHtml -match "(?i)logout\.cgi" -and $rebootHtml -notmatch "(?i)System Reboot|Reboot performs|name=[""']isReset[""']") {
    Clear-Secrets
    throw "Login session not accepted. Try again, or login once in browser then retry."
}
if ($rebootHtml -notmatch "(?i)name=[""']isReset[""']") {
    Clear-Secrets
    throw "Reboot page did not load. Check debug HTML in $debugDir"
}

Write-Host "[4/4] Sending Reboot (isReset=1)..." -ForegroundColor Yellow

# Browser JS does: f.isReset.value = 1; f.submit();
$rebootToken = Get-HiddenValue $rebootHtml "authToken"
if ([string]::IsNullOrWhiteSpace($rebootToken)) {
    Clear-Secrets
    throw "Reboot authToken missing."
}

Write-FormBody ([ordered]@{
    authToken = $rebootToken
    isReset   = "1"
}) $bodyFile

$out = Join-Path $env:TEMP "huawei_reboot_try_1.html"
$code = & curl.exe @curlCommon `
    -c $cookieJar -b $cookieJar `
    -A "Mozilla/5.0" `
    -H "Referer: $RouterUrl/reboot.cgi" `
    -H "Content-Type: application/x-www-form-urlencoded" `
    --data-binary "@$bodyFile" `
    -o $out -w "%{http_code}" `
    "$RouterUrl/reboot.cgi"
Remove-Item $bodyFile -ErrorAction SilentlyContinue
Save-DebugCopy $out "04-reboot-try-1.html"
Write-Host ("      POST reboot.cgi isReset=1 -> HTTP {0} (curl exit {1})" -f $code, $LASTEXITCODE)

$triggered = $false
if ($LASTEXITCODE -in 7, 28, 56) {
    $triggered = $true
    Write-Host "      Connection dropped (normal during reboot)." -ForegroundColor Green
}
elseif ($code -in @("200", "302", "303", "000")) {
    $body = if (Test-Path $out) { Get-Content $out -Raw } else { "" }
    if ($body -match '(?i)NAME=["'']isReset["'']\s+VALUE=["'']0["'']' -and $body -match "(?i)System Reboot") {
        $triggered = $false
    }
    else {
        $triggered = $true
    }
}

Clear-Secrets

if (-not $triggered) {
    Write-Host ""
    Write-Host "Reboot may not have triggered. Debug HTML:" -ForegroundColor Red
    Write-Host "  $debugDir"
    exit 1
}

Write-Host ""
Write-Host "Reboot command sent." -ForegroundColor Green
Write-Host "Router usually takes 1-3 minutes to come back." -ForegroundColor Green

if ($WaitOnline) {
    Write-Host ""
    Write-Host "Waiting for router..." -ForegroundColor Yellow
    Start-Sleep -Seconds 20
    $hostName = ([uri]$RouterUrl).Host
    for ($i = 1; $i -le 36; $i++) {
        if (Test-Connection -ComputerName $hostName -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Write-Host "Router is back online." -ForegroundColor Green
            if (-not $Auto) {
                Write-Host "Press Enter to close."
                [void][Console]::ReadLine()
            }
            exit 0
        }
        Write-Host ("  ping {0}/36..." -f $i)
        Start-Sleep -Seconds 5
    }
    Write-Host "Still waiting — check Wi-Fi/LAN manually." -ForegroundColor Yellow
}

if (-not $Auto) {
    Write-Host ""
    Write-Host "Done. Press Enter to close."
    [void][Console]::ReadLine()
}
