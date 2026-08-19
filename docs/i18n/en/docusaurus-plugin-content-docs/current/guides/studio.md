---
sidebar_position: 11
---

# OrvexORM Studio

OrvexORM Studio is a **web interface** that lets you visualize and manage your database directly from your browser. Like Prisma Studio, but for FiveM. **Zero dependencies, 100% Lua.**

The studio works with both **oxmysql** and **mysql-async**: its queries are routed through the ORM adapter, so whichever library your server uses is fine.

## Launch

No installation required. The studio is built directly into the orvexorm resource.

### From the txAdmin console

Simply type:

```
orvexstudio
```

The studio will:
1. Generate a **secret token** from the operating system's random source, or use `orvex_studio_token` when it contains at least 32 characters
2. Enable the resource's built-in web routes
3. Display the access URL in the console

```
══════════════════════════════════════════════════
  OrvexORM Studio
══════════════════════════════════════════════════

  URL : http://localhost:30120/orvexorm/?token=a1b2c3d4e5f6...

  Share this URL only with trusted people.
  Type 'orvexstudio stop' to stop.

══════════════════════════════════════════════════
```

To stop:
```
orvexstudio stop
```

### Remote access

If you're on a dedicated server, replace `localhost` with your server IP:
```
http://123.45.67.89:30120/orvexorm/?token=a1b2c3d4...
```

Port `30120` is the FiveM HTTP port (same as your server).

## Security

The studio is protected by a **random token** regenerated on every start. If the operating system random source is unavailable, startup fails instead of creating a predictable token. You can provide a stable token with `set orvex_studio_token "..."`; it must contain at least 32 characters.

- The initial token is carried in the URL, then removed from the address bar and sent in the `X-Studio-Token` header
- No authentication cookie is created
- The token expires after **30 minutes**; run `orvexstudio` again to start a new session
- Without the token, all requests return `403 Access Denied`
- **Brute-force protection**: an IP is locked out for 5 minutes after 5 invalid tokens
- Requests are limited to **120 per minute per address**, and request bodies to **1 MiB**

:::caution
OrvexORM Studio is a **development tool** that gives full access to your database. The endpoint is exposed on the **public game port 30120**, so anyone who obtains the URL can reach it. The token is regenerated on every start, but the safest habit is to stop the studio (`orvexstudio stop`) as soon as you're done.
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
