# Huawei B2368-66 Auto Reboot

**Repo:** https://github.com/iramyaseen/huawei-b2368-auto-reboot

One-click PowerShell automation that reboots a **Huawei LTE CPE B2368-66** without opening the web UI.

Built to solve a real daily pain: unstable LTE CPE that needs frequent restarts, but the admin UI forces a multi-step flow every time.

## Problem

On this router, a simple reboot means:

1. Open `https://192.168.1.1/login.cgi`
2. Enter username / password
3. Dismiss the **Change Password** prompt (**Skip**)
4. Open **Maintenance → Reboot**
5. Confirm reboot

Doing that several times a day wastes time — and it’s easy to miss a step.

## Solution

A local script that talks to the same CGI endpoints the browser uses:

| Step | What the script does |
|------|----------------------|
| Login | Fetches a fresh `authToken`, Base64-encodes the password (`hiddenPassword`), POSTs to `login.cgi` |
| Skip | POSTs `submitValue=0` + `authToken` to `indexMain.cgi` (not a plain GET) |
| Reboot | Loads `reboot.cgi`, then POSTs `isReset=1` + `authToken` |
| Wait | Optionally pings until the router is back online |

## Why a “simple POST” was not enough

Reverse-engineering the B2368 UI showed a few non-obvious details:

- Login requires a page-specific **`authToken`**
- Password is sent as **Base64** in `hiddenPassword`, not plain text
- **Skip** is a form POST (`submitValue=0`), not just opening the main page
- Reboot only happens when **`isReset=1`** — posting the default `isReset=0` reloads the page and does nothing
- The device’s `mini_httpd` + HTTPS stack is picky (`HTTP/1.0`, self-signed cert, abrupt SSL close)

## Quick start

1. Copy the example config:

```powershell
copy config.example.json config.json
```

2. Edit `config.json` with your router credentials.
3. Double-click `Reboot-Router.bat`  
   or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\huawei-b2368-reboot.ps1 -Auto -WaitOnline
```

You must be on the same LAN/Wi‑Fi as the router (`192.168.1.1`).

## Security notes

- `config.json` is gitignored — **do not commit passwords**
- Use this only on routers you own / administer
- Prefer changing the factory default password after first setup

## Skills demonstrated

- Reverse-engineering a legacy CGI web UI
- Session + CSRF-style token handling (`authToken`)
- HTTP form automation with `curl` on Windows
- Debugging SSL / `mini_httpd` quirks
- Turning a manual ops chore into a one-click tool

## Disclaimer

Unofficial tool for personal/lab use. Huawei firmware varies; paths and fields may differ on other models. Not affiliated with Huawei.

## License

MIT
