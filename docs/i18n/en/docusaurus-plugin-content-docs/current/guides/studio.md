---
sidebar_position: 11
---

# OrvexORM Studio

OrvexORM Studio is a **web interface** that lets you visualize and manage your database directly from your browser. Like Prisma Studio, but for FiveM. **Zero dependencies, 100% Lua.**

## Launch

No installation required. The studio is built directly into the orvexorm resource.

### From the txAdmin console

Simply type:

```
orvexstudio
```

The studio will:
1. Automatically read the `mysql_connection_string` from your `server.cfg`
2. Generate a **secret security token**
3. Start the built-in web server
4. Display the secure URL in the console

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

The studio is protected by a **random token** generated on each launch. Only people who can see the txAdmin console have access to the URL.

- The token is in the URL: `http://localhost:30120/orvexorm/?token=...`
- After the first connection, a cookie is set (valid 24h)
- Without the token, all requests return `403 Access Denied`

:::caution
OrvexORM Studio is a **development tool**. Never expose it on a publicly accessible server. It gives full access to your database.
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
- **Edit a row**: click on a row to open the editor
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
