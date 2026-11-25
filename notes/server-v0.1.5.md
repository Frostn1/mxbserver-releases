mxbserver 0.1.5 offers every official OEM bike with no setup.

**Downloads**

- Windows 10/11 x64: `mxbserver-x86_64-pc-windows-msvc.exe`, signed by Creste LLC
- Linux x86-64: `mxbserver-x86_64-unknown-linux-gnu.elf`

**Bikes**

Leave the bike settings out and the server offers MX1 OEM, MX2 OEM, MX1-2T OEM, MX2-2T OEM, MX3 OEM and MX-E OEM. The bike data is built in, so no bike-set files are needed. To narrow it:

```toml
[server]
bikes = "mx2"   # or "all" (default), "mx1", "mx3", "mxe", or a list of those and bike ids
```

A player missing a bike still joins; they just can't pick that bike. On a player's first join they ride the bike they picked, and from their next join every bike they own is in their list. Mod bike sets in a `mod-bikes` folder next to the config are offered too. `[bike_set]` and `[bike_sets]` configs work as before. The 1996-2003 two-strokes are not offered yet.

Setting up a server with bots: [docs/dedicated-server-with-bots.md](https://github.com/Frostn1/mxbserver-releases/blob/main/docs/dedicated-server-with-bots.md).
