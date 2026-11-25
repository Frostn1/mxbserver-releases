# Run a dedicated server with bots

mxbserver is a dedicated MX Bikes server for Linux and Windows. It can fill your server with
bots that ride the track, race from the gate, and make room when players join.

## 1. Download

From the newest `mxbserver` release on the [Releases page](https://github.com/Frostn1/mxbserver-releases/releases):

| System | File |
| --- | --- |
| Windows 10/11 x64 | `mxbserver-x86_64-pc-windows-msvc.exe` (signed by Creste LLC) |
| Linux x86-64 | `mxbserver-x86_64-unknown-linux-gnu.elf` |

Put the server and your track in one folder. The OEM bikes are built in, so there is nothing
else to download:

```
my-server/
  mxbserver.exe             (or mxbserver-x86_64-unknown-linux-gnu.elf)
  mxbserver.toml
  tracks/my-track.pkz
```

The track is the track's `.pkz` from your `mods/tracks` folder. Locked (encrypted) track
packages can't be read by the server; use an ordinary one.

## 2. server.toml

Save this as `mxbserver.toml`. Paths are relative to this file.

```toml
[server]
name = "My MXB Server"
listen = "0.0.0.0:54210"     # the UDP port riders join on
max_clients = 20
password = ""                # set one to make the server private

[track]
package = "tracks/my-track.pkz"

[master]
enable = true                # show the server in the in-game browser

[sessions]
practice_minutes = 15
race_minutes = 15
race_countdown_seconds = 30

[ghost]
count = 8                    # how many bots ride
synth = true                 # bots ride from the first start, no recording needed
bikes = "random"             # one bike each from the bikes on offer
racing = "neutral"           # race normally, with grid starts
name = "Bot"
harvest = "ghosts/library"   # save players' clean laps
library = "ghosts/library"   # and let the bots ride them

[ghost.personality]
skill_spread_pct = 6         # some bots are faster than others
consistency_pct = 2          # lap times vary a little
mistakes_per_hour = 4        # bots crash now and then
```

## 3. Start it

Windows (PowerShell, in the folder):

```powershell
.\mxbserver-x86_64-pc-windows-msvc.exe --config mxbserver.toml
```

Linux:

```sh
chmod +x mxbserver-x86_64-unknown-linux-gnu.elf
./mxbserver-x86_64-unknown-linux-gnu.elf --config mxbserver.toml
```

Open the UDP port from `listen` (54210 above) in your firewall and router. The console prints
the track, the bikes and one `bot` line per bot. The server shows up in the in-game browser
within a minute.

## Bikes

Every official OEM bike is on offer with no setting: MX1 OEM, MX2 OEM, MX1-2T OEM, MX2-2T OEM,
MX3 OEM and MX-E OEM. To narrow it, add one line under `[server]`:

```toml
bikes = "mx2"                # or "all", "mx1", "mx3", "mxe", or a list: ["mx2", "MX1OEM_2023_Yamaha_YZ450F"]
```

A player who doesn't own a bike just can't pick it; they still join. The first time a player
joins, they ride the bike they picked; from their next join on, every bike they own is in their
list. Mod bike sets (`.toml`) in a `mod-bikes` folder next to `mxbserver.toml` are offered too.
Old `[bike_set]` settings keep working.

## Bots

| Setting | What it does |
| --- | --- |
| `count` | How many bots ride. |
| `fill_to` | Keep players plus bots at this many riders: a bot steps out for each player who joins. Use it instead of `count`. |
| `bikes` | `"random"`, or a list of bike ids used in turn: `["MX2OEM_2023_KTM_250_SX-F", "MX2OEM_2024_Yamaha_YZ250F"]`. |
| `racing` | `"neutral"` races normally. `"yield"` also moves aside for players on straights. `"block"` defends its line. |
| `skill_pct` | Bot pace in percent of the lap they ride (50 to 150). |
| `synth` | With no recording and no saved laps yet, bots ride a lap made from the track. |

`[ghost.personality]` makes every bot a rider of its own:

| Setting | What it does |
| --- | --- |
| `skill_spread_pct` | Pace spread between bots, percent (0 to 30). |
| `consistency_pct` | Lap-to-lap variation, percent (0 to 10). |
| `mistakes_per_hour` | Crashes per bot per hour (0 to 60). |
| `racecraft_mix` | Share of bots that yield, race neutral or block a player behind them, e.g. `[0.5, 0.4, 0.1]`. |
| `seed` | The same seed gives the same set of bots every time. |

## Record your own line

Bots can ride your laps instead of the made-up one. Add this, restart, and ride 2 or 3 clean
laps with race number 41:

```toml
[ghost]
record = "ghosts/me.mxgh"
record_plate = 41
```

The console shows `recording rider #41`. Then point the bots at it and restart. Take out the
`library` line, or the bots keep riding the saved laps instead:

```toml
[ghost]
replay = "ghosts/me.mxgh"
count = 8
bikes = "random"
racing = "neutral"
```

With `harvest` and `library` set (as in the config above), you don't need to record anything:
every player's clean laps are saved and the bots start riding them once the track has some.

## Race start

With `racing` set, bots line up on the gate with the players, wait for the drop and launch
with everyone. `race_countdown_seconds` sets the countdown before the gate. To keep bots out
of the race start, set `race_starts = false` under `[ghost]`.

## Password

Set `password` under `[server]`. Players type it when they join from the in-game browser.
After 5 wrong tries an address is locked out for 10 minutes.

## Welcome and repeating messages

Greet each rider when they join, and post a line to everyone every few minutes:

```toml
[messages]
greeting = ["Welcome to My MXB Server", "Be nice, no blocking"]

[[messages.repeat]]
text = "Join our Discord: discord.gg/yourcode"
every_min = 15
```

Each line is up to 99 characters. Changes apply without a restart. In MXB Servers, the same
settings are under Settings > Messages.

## Check it is running

Add `observe = "127.0.0.1:9808"` under `[server]` and open http://127.0.0.1:9808/status on
the server machine. It shows the track, the session, and how many players and bots are on.

## Check the download

```sh
sha256sum -c SHA256SUMS --ignore-missing
minisign -V -p minisign.pub -m SHA256SUMS
```

`minisign.pub` is at the root of this repo.

## MXB Servers

[MXB Servers](https://github.com/Frostn1/mxbserver-releases/releases) is the Windows app that
manages mxbserver. Its Riders & bots and Bot behaviour pages set the same bot options without
editing the file.
