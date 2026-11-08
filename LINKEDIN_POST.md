# LinkedIn post — copy/paste

---

I got tired of clicking through my Huawei LTE CPE (B2368-66) just to reboot it.

Every unstable connection meant this manual loop:

Login → Skip “Change Password” → Maintenance → Reboot → Confirm

So I reverse-engineered the router’s CGI web UI and built a one-click PowerShell automation.

What made it interesting (not a plain API call):

1️⃣ Login needs a fresh `authToken` from the page  
2️⃣ Password is Base64-encoded before POST  
3️⃣ “Skip” is a real form submit (`submitValue=0`)  
4️⃣ Reboot only works when `isReset=1` — otherwise the page just reloads  

Core flow in code:

```powershell
# 1) Login — authToken + Base64 password
$hiddenPassword = [Convert]::ToBase64String(
  [Text.Encoding]::UTF8.GetBytes($Password)
)

# POST login.cgi
# UserName, hiddenPassword, authToken, submitValue=1
```

```powershell
# 2) Skip "Change Password" prompt
# POST indexMain.cgi
# authToken + submitValue=0
```

```powershell
# 3) Actual reboot (this is the key!)
# POST reboot.cgi
# authToken + isReset=1
```

Without `isReset=1`, the router returns the same Reboot page and does nothing — that bug cost me a debug cycle.

Result: double-click `Reboot-Router.bat` → full reboot flow, then wait until the CPE is back online.

Repo: https://github.com/iramyaseen/huawei-b2368-auto-reboot

Stack: PowerShell · curl · CGI reverse engineering · session/token handling

#PowerShell #Networking #Automation #HomeLab #ProblemSolving #Scripting

---

## Short version (agar chhoti post chahiye)

Huawei B2368 pe har baar manually reboot karna padta tha (login → skip → maintenance → reboot).

Maine CGI flow reverse-engineer karke one-click PowerShell script banayi:

```powershell
# Login:  authToken + Base64(password) → login.cgi
# Skip:   submitValue=0                 → indexMain.cgi
# Reboot: isReset=1                     → reboot.cgi
```

Ab double-click se poora flow auto ho jata hai.

GitHub: https://github.com/iramyaseen/huawei-b2368-auto-reboot

#PowerShell #Automation #Networking #HomeLab
