mxbserver 0.1.3 adds join greetings and repeating messages.

**Downloads**

- Windows 10/11 x64: `mxbserver-x86_64-pc-windows-msvc.exe`, signed by Creste LLC
- Linux x86-64: `mxbserver-x86_64-unknown-linux-gnu.elf`
- Bike sets: `oem-mx2.toml`, `oem-mx1.toml`

**Welcome and repeating messages**

```toml
[messages]
greeting = ["Welcome to My MXB Server", "Be nice, no blocking"]

[[messages.repeat]]
text = "Join our Discord: discord.gg/yourcode"
every_min = 15
```

Each rider gets the greeting once when they join. Repeating messages go to everyone on the server at their interval. Each line is up to 99 characters, and changes apply without a restart. MXB Servers 0.7.6 edits them under Settings > Messages.

Setting up a server with bots: [docs/dedicated-server-with-bots.md](https://github.com/Frostn1/mxbserver-releases/blob/main/docs/dedicated-server-with-bots.md).
