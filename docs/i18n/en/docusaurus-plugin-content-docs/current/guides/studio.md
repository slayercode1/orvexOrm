---
sidebar_position: 11
---

# OrvexORM Studio

OrvexORM Studio is a **web interface** that lets you visualize and manage your database directly from your browser. It's like Prisma Studio, but for FiveM.

## Launch

No installation required. The studio is 100% Lua, built directly into the orvexorm resource. It works with **oxmysql** and **mysql-async**: its queries are routed through the ORM adapter, whichever library is installed.

### From the txAdmin console

Simply type in the console:

```
orvexstudio
```

The studio:
1. Generates a **secret token** from the system's secure random source, or uses the `orvex_studio_token` convar if it holds at least 32 characters
2. Enables the web routes built into the resource
3. Prints the access URL in the console

```
══════════════════════════════════════════════════
  OrvexORM Studio
══════════════════════════════════════════════════

  URL : http://localhost:30120/orvexorm/?token=a1b2c3d4e5f6...

  Allowed addresses : 127.0.0.1, ::1 (convar orvex_studio_allow)

  Share this URL only with trusted people.
  Traffic is plain HTTP: from a remote machine, use an SSH tunnel
  (ssh -L 30120:127.0.0.1:30120 user@server) instead of widening the allowlist.
  Stop the Studio as soon as you are done.
  Type 'orvexstudio stop' to stop.
  This Studio session expires after 30 minutes.

══════════════════════════════════════════════════
```

To stop it:
```
orvexstudio stop
```

### Remote access: SSH tunnel (recommended)

By default, the Studio **only answers local connections** (`127.0.0.1` and `::1`). If your server is remote, do not open the Studio to the network: create an SSH tunnel from your computer, which makes your connection look local.

```bash
# On your computer
ssh -L 30120:127.0.0.1:30120 user@your-server
```

Keep that terminal open, then open the URL printed in the console, as is, in your browser:

```
http://localhost:30120/orvexorm/?token=a1b2c3d4...
```

Port `30120` is FiveM's HTTP port (the same as your server). If your server uses another port, adjust both sides of the tunnel (`-L 30120:127.0.0.1:<port>`).

### Allowing other addresses: `orvex_studio_allow`

The `orvex_studio_allow` convar lists the allowed addresses. It is read **when `orvexstudio` starts**: change it before starting the Studio (or run `orvexstudio stop` then `orvexstudio`).

```cfg title="server.cfg (or console)"
# Default: loopback only
set orvex_studio_allow "127.0.0.1, ::1"

# Add a LAN machine and an IPv4 range
set orvex_studio_allow "127.0.0.1, ::1, 192.168.1.20, 10.0.0.0/24"

# Any address (not recommended)
set orvex_studio_allow "*"
```

| Entry | Example | Effect |
|---|---|---|
| Exact IPv4 or IPv6 address | `192.168.1.20`, `::1` | Allows that address |
| IPv4 CIDR range | `10.0.0.0/24` | Allows the whole range |
| `*` | `*` | Allows every address |

Entries are separated by commas or spaces. An invalid entry is ignored (a message is printed in the console); if no entry is valid, **nobody** is allowed. An empty value falls back to the default.

:::danger Traffic is plain HTTP
The Studio has no HTTPS: when you widen the list, the token and your database contents travel **in cleartext** over the network. Always prefer the SSH tunnel.
:::

:::caution Behind a proxy (txAdmin, reverse proxy)
Behind a proxy, the address the Studio sees is **the proxy's**, for every client. The allowlist, the request limit and the brute-force lockout then apply to the proxy as a whole. Never allow the address of a proxy exposed to the internet.
:::

## Security

The studio is protected by a **random token** generated on every launch. If the system's secure random source is unavailable, startup fails instead of creating a predictable token. You can provide a stable token with `set orvex_studio_token "..."`; it must contain at least 32 characters.

- **Network filtering**: a request from an address outside `orvex_studio_allow` gets a plain `404 Not Found`, with no log
- Stopped Studio: every request gets the same `404 Not Found` (no log, nothing reveals that it exists)
- The token in the URL (`?token=`) is accepted **only for the first page load**. The page removes it from the address bar, keeps it in memory and then sends it in the `X-Studio-Token` header. The `/api/*` routes refuse the token as a URL parameter (`403`)
- Reloading the page after the token was removed gives a `403`: reopen the URL printed in the console
- No authentication cookie is created
- The token expires after **30 minutes**; run `orvexstudio` again to start a new session
- Without a valid token, the request returns `403`
- **Brute-force protection**: an IP is locked out for **5 minutes** after **5 invalid tokens**
- Requests are limited to **120 per minute per address** (checked before the token), and request bodies to **1 MiB**
- Rejections for the request limit or the lockout are logged **once** per window or per lockout, not on every request
- The page is served with a strict CSP (scripts and styles limited to a per-load nonce) and row data is always inserted as text: a value stored by a player cannot run a script in your browser

:::caution
OrvexORM Studio is a **development tool**. While it runs, anyone with the token **and** an allowed address has full access to your database. The token is regenerated on every start, but the safest habit is to stop the studio (`orvexstudio stop`) as soon as you're done.
:::

## Features

### View all tables

The left panel displays all tables in your database with the row count. Click on a table to view its contents.

### Browse data

- **Pagination**: navigate page by page (10, 25, 50 or 100 rows per page)
- **Sorting**: click on a column header to sort (ASC/DESC)
- **Filters**: filter data by column with operators `=`, `!=`, `>`, `<`, `LIKE`, `IS NULL`, etc.

### Edit data

- **Add a row**: click "Add Row", fill in the form, and submit
- **Edit a row**: use the row's edit button to open the editor
- **Delete a row**: click the delete button (with confirmation)

Form fields automatically adapt to the column type:

| MySQL Type | Field |
|---|---|
| VARCHAR, TEXT | Text input |
| INT, BIGINT, FLOAT | Number input |
| TINYINT(1) | Checkbox |
| JSON | Text area |
| DATE | Date picker |
| DATETIME | Date + time picker |
| ENUM | Dropdown |

### View schema

The "Schema" tab displays the table structure (columns, types, keys, default values).

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Escape` | Close modal |

## Customizing `studio.html`

The page is served with a CSP without `'unsafe-inline'`. If you edit `studio.html`:

- do not add inline `onclick` / `style` attributes: they would be blocked;
- keep the `{{NONCE}}` placeholder on the `<script>` and `<style>` tags (`<script nonce="{{NONCE}}">`), replaced on every load by a random nonce;
- never insert a row value with `innerHTML`: use `textContent` or `.value`.
