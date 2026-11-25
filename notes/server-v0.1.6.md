mxbserver 0.1.6 fixes two Windows host problems.

**Downloads**

- Windows 10/11 x64: `mxbserver-x86_64-pc-windows-msvc.exe`, signed by Creste LLC
- Linux x86-64: `mxbserver-x86_64-unknown-linux-gnu.elf`

**Fixes**

- A `listen` address that isn't on the machine, such as your public IP behind a router, no longer stops the server with os error 10049. The server listens on every address on that port, prints one warning with the fix (`listen = "0.0.0.0:<port>"`), and keeps that IP as the LAN address in its master listing.
- Console colours show properly on Windows instead of codes like `←[36m`.

Includes everything in 0.1.5: every official OEM bike is offered with no setup.

Setting up a server with bots: [docs/dedicated-server-with-bots.md](https://github.com/Frostn1/mxbserver-releases/blob/main/docs/dedicated-server-with-bots.md).
