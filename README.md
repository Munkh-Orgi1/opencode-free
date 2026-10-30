# opencode-free

One double-click launcher for the **OpenCode desktop app** that keeps the free
quota alive by moving your egress IP.

OpenCode's free models are limited per IP. When the limit is hit, the app
answers `Free usage limit reached`. This launcher starts the app behind a local
[Cloudflare WARP](https://1.1.1.1) proxy, watches the OpenCode log, and when
that line appears it closes the app, drops the WARP registration, requests a
new one (new exit IP = fresh free quota) and opens the app again on the same
session. No input needed.

```
double-click  ->  new WARP exit IP  ->  OpenCode opens
limit reached ->  app closes, IP rotates, app reopens
```

## Requirements

- Windows 10 / 11
- [OpenCode desktop](https://opencode.ai)
- [Cloudflare WARP](https://1.1.1.1) client (free). If it is missing the
  launcher still runs, just without rotation.

Nothing else. No Node, no admin rights, no registry changes, no services.

## Install

Download the single file to your Desktop:

```powershell
iwr https://raw.githubusercontent.com/Munkh-Orgi1/opencode-free/main/OpenCode%20Free.bat -OutFile "$env:USERPROFILE\Desktop\OpenCode Free.bat"
```

or `git clone` the repo and copy `OpenCode Free.bat` anywhere you like.
The file is self-contained: the batch header extracts its own PowerShell
payload to `%TEMP%` and runs it.

## Usage

1. Double-click **OpenCode Free.bat**.
2. The console stays open and shows what it does. The app opens by itself.
3. Use OpenCode normally.
4. On a quota error it rotates and reopens the app automatically.
5. Close the console window to stop watching. The app keeps running;
   it just will not rotate any more.

Double-clicking the file again while it is running is safe: the new instance
stops the old watcher first, rotates, and reopens the app.

## How it works

`OpenCode.exe` is an Electron shell around `resources\opencode-cli.exe`, and
Windows passes environment variables down to child processes. The launcher

1. sets `warp-cli mode proxy` and puts the WARP HTTP proxy on `127.0.0.1:40000`
2. exports `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` and starts `OpenCode.exe`
   from that environment, so the CLI child does its model traffic through WARP
3. tails `~/.local/share/opencode/log/opencode.log`
4. on `Free usage limit reached` / `Rate limit exceeded`: kills the app tree,
   runs `warp-cli registration delete` + `registration new`, waits for the
   tunnel, and starts the app again

Sessions live in `~/.local/share/opencode`, so a restart does not lose them.

## Configuration

All settings are environment variables; the defaults are sane.

| variable        | default | meaning                                            |
|-----------------|---------|----------------------------------------------------|
| `OC_PROXY_PORT` | `40000` | local WARP proxy port                              |
| `OC_COOLDOWN`   | `45`    | seconds between two rotations                      |
| `OC_NO_ROTATE`  | unset   | `1` = no rotation (plain launch)                   |
| `OC_APP`        | auto    | full path to `OpenCode.exe`                        |
| `OC_WARP`       | auto    | full path to `warp-cli.exe`                        |

Example (launch with a longer cooldown):

```bat
set OC_COOLDOWN=120
"OpenCode Free.bat"
```

## Troubleshooting

| symptom | cause / fix |
|---|---|
| `[warp] not installed` | install Cloudflare WARP; the app still runs direct |
| `[warp] rotation failed` | WARP service stopped, or Cloudflare throttled a burst of registrations - wait a minute and start again |
| model calls fail right after start | WARP tunnel not up yet; close the app, start the launcher again |
| `[limit]` never fires | the free tier changed its wording - update `$Fatal` in the payload |
| app does not open | set `OC_APP` to the real `OpenCode.exe` path |

Log line used for detection, for reference:

```
level=ERROR ... cause="AI.Error: Free usage limit reached. Subscribe to OpenCode Go ..."
```

## Limitations

- Only the OpenCode CLI traffic is proxied; the GUI's own web requests are not.
- MCP servers started by OpenCode inherit the proxy too.
- Rotation helps while the free tier limits by IP. If it becomes account-based,
  a new IP will not mint new quota.
- WARP is left in `proxy` mode. Restore the normal behaviour with
  `warp-cli mode warp`.

## License

MIT. See [LICENSE](LICENSE).

---

## Монгол

**OpenCode Free.bat** — OpenCode desktop-ыг Cloudflare WARP-аар эхлүүлж,
үнэгүй лимит хүрэх бүрд WARP-ийн exit IP-г сольж, app-ыг өөрөө дахин асгадаг
нэг файл.

1. `OpenCode Free.bat`-ыг double click
2. OpenCode өөрөө нээгдэнэ, console цонх хянаж байна
3. Лимит хүрвэл (`Free usage limit reached`) app хаагдаж, шинэ IP авч, дахин нээгдэнэ
4. Зогсоох: console цонхыг хаа

Шаардлага: Windows 10/11, OpenCode desktop, Cloudflare WARP (1.1.1.1).
WARP байхгүй бол rotate хийхгүй, зүгээр нээгдэнэ.
