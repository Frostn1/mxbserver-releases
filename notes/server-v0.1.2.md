mxbserver 0.1.2 runs on Windows and Linux.

**Downloads**

- Windows 10/11 x64: `mxbserver-x86_64-pc-windows-msvc.exe`, signed by Creste LLC
- Linux x86-64: `mxbserver-x86_64-unknown-linux-gnu.elf`
- Bike sets: `oem-mx2.toml`, `oem-mx1.toml`

**Run a dedicated server with bots**

Put the server, a bike set and a track `.pkz` in one folder, save this as `mxbserver.toml` and start the server with `--config mxbserver.toml`:

```toml
[server]
name = "My MXB Server"
listen = "0.0.0.0:54210"
password = ""

[track]
package = "tracks/my-track.pkz"

[bike_set]
manifest = "bike-sets/oem-mx2.toml"

[master]
enable = true

[ghost]
count = 8
synth = true
bikes = "random"
racing = "neutral"
harvest = "ghosts/library"
library = "ghosts/library"

[ghost.personality]
skill_spread_pct = 6
mistakes_per_hour = 4
```

Open UDP 54210 in your firewall. Bots ride from the first start, line up on the gate for races, and start riding your players' saved laps as they come in. The full guide, with recording your own line, is in [docs/dedicated-server-with-bots.md](https://github.com/Frostn1/mxbserver-releases/blob/main/docs/dedicated-server-with-bots.md).

**What's new**

- Windows build.
- Join password: set `password` under `[server]`; players type it in the game. After 5 wrong tries an address is locked out for 10 minutes.
- Track owners can upload their own track to a hosted server from MXB Servers.
- The status page stays on the server machine unless you allow remote access.
- Security fixes and updated network libraries.
