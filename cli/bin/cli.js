#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const VERSION = require('../package.json').version;
const NAME = 'orvexorm';

// Colors
const c = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m',
};

function log(msg) { console.log(msg); }
function success(msg) { log(`  ${c.green}✓${c.reset} ${msg}`); }
function error(msg) { log(`  ${c.red}✗${c.reset} ${msg}`); }
function info(msg) { log(`  ${c.dim}${msg}${c.reset}`); }

function banner() {
  log('');
  log(`  ${c.cyan}${c.bold}OrvexORM${c.reset} ${c.dim}v${VERSION}${c.reset}`);
  log(`  ${c.dim}Lightweight ORM for FiveM${c.reset}`);
  log('');
}

function help() {
  banner();
  log(`  ${c.bold}Usage:${c.reset}`);
  log(`    npx orvexorm ${c.cyan}<command>${c.reset} [options]`);
  log('');
  log(`  ${c.bold}Commands:${c.reset}`);
  log(`    ${c.cyan}install${c.reset} [dir]     Install OrvexORM into your FiveM server`);
  log(`    ${c.cyan}update${c.reset}  [dir]     Update an existing installation`);
  log(`    ${c.cyan}init${c.reset}    [name]    Scaffold a new resource using OrvexORM`);
  log(`    ${c.cyan}version${c.reset}           Show version`);
  log(`    ${c.cyan}help${c.reset}              Show this help`);
  log('');
  log(`  ${c.bold}Examples:${c.reset}`);
  log(`    ${c.dim}npx orvexorm install${c.reset}                    ${c.dim}# Auto-detect resources/${c.reset}`);
  log(`    ${c.dim}npx orvexorm install ./resources/orvexorm${c.reset}`);
  log(`    ${c.dim}npx orvexorm init my-resource${c.reset}`);
  log('');
}

function detectTarget(arg) {
  if (arg && !arg.startsWith('--')) return path.resolve(arg);
  if (fs.existsSync('resources')) return path.resolve('resources', NAME);
  if (fs.existsSync('../resources')) return path.resolve('..', 'resources', NAME);
  if (fs.existsSync('server.cfg')) return path.resolve('resources', NAME);
  return path.resolve(NAME);
}

// Recursively copy a directory
function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function isOrvexInstallation(dir) {
  const manifest = path.join(dir, 'fxmanifest.lua');
  if (!fs.existsSync(manifest)) return false;
  try {
    const content = fs.readFileSync(manifest, 'utf-8');
    return content.includes("provide 'orvexorm'") || content.includes("name 'orvexorm'");
  } catch {
    return false;
  }
}

function install(targetDir) {
  banner();
  log(`  ${c.bold}Installing OrvexORM...${c.reset}`);
  log('');

  const target = detectTarget(targetDir);
  log(`  ${c.bold}Target:${c.reset} ${target}`);
  log('');

  // The compiled dist is bundled inside this npm package
  const distDir = path.join(__dirname, '..', 'dist');

  if (!fs.existsSync(distDir)) {
    error('Distribution files not found in the package.');
    error('The npm package may be corrupted. Try reinstalling:');
    log(`    ${c.bold}npx orvexorm@latest install${c.reset}`);
    process.exit(1);
  }

  try {
    // Remove existing — but only if it looks like an OrvexORM installation
    if (fs.existsSync(target)) {
      if (!isOrvexInstallation(target)) {
        error(`"${target}" exists but doesn't look like an OrvexORM installation.`);
        error('If you are sure, remove it manually first.');
        process.exit(1);
      }
      info('Removing existing installation...');
      fs.rmSync(target, { recursive: true, force: true });
    }

    // Copy bundled dist to target
    info('Copying OrvexORM files...');
    copyDir(distDir, target);
  } catch (err) {
    if (err.code === 'EACCES' || err.code === 'EPERM') {
      error(`Permission denied writing to "${target}".`);
      error('Try running with elevated permissions or choose a different directory.');
    } else {
      error(`Failed to install: ${err.message}`);
    }
    process.exit(1);
  }

  // Count installed files
  let fileCount = 0;
  function countFiles(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory()) countFiles(path.join(dir, entry.name));
      else fileCount++;
    }
  }
  countFiles(target);

  log('');
  success(`OrvexORM installed at ${c.bold}${target}${c.reset}`);
  info(`${fileCount} files installed (compiled bytecode)`);
  log('');
  log(`  ${c.bold}Next steps:${c.reset}`);
  log('');
  log(`  1. Add to ${c.cyan}server.cfg${c.reset}:`);
  log(`     ${c.bold}ensure oxmysql${c.reset}`);
  log(`     ${c.bold}ensure orvexorm${c.reset}`);
  log('');
  log(`  2. In your resource ${c.cyan}fxmanifest.lua${c.reset}:`);
  log(`     ${c.bold}dependency 'orvexorm'${c.reset}`);
  log(`     ${c.bold}server_script '@orvexorm/lib/import.lua'${c.reset}`);
  log('');
  log(`  3. Use it:`);
  log(`     ${c.bold}local User = OrvexORM.model("users", { ... })${c.reset}`);
  log('');
}

function update(targetDir) {
  banner();
  log(`  ${c.bold}Updating OrvexORM...${c.reset}`);
  log('');

  const target = detectTarget(targetDir);

  if (!fs.existsSync(target)) {
    error(`OrvexORM not found at "${target}".`);
    error('Use "npx orvexorm install" to install first.');
    process.exit(1);
  }

  log(`  ${c.bold}Target:${c.reset} ${target}`);
  log('');

  const distDir = path.join(__dirname, '..', 'dist');

  if (!fs.existsSync(distDir)) {
    error('Distribution files not found in the package.');
    process.exit(1);
  }

  try {
    info('Removing old version...');
    fs.rmSync(target, { recursive: true, force: true });

    info('Installing new version...');
    copyDir(distDir, target);
  } catch (err) {
    if (err.code === 'EACCES' || err.code === 'EPERM') {
      error(`Permission denied writing to "${target}".`);
    } else {
      error(`Failed to update: ${err.message}`);
    }
    process.exit(1);
  }

  log('');
  success(`OrvexORM updated at ${c.bold}${target}${c.reset}`);
  log('');
}

function init(resourceName) {
  banner();

  if (!resourceName) {
    error('Please provide a resource name: npx orvexorm init my-resource');
    process.exit(1);
  }

  if (!/^[a-zA-Z0-9_-]+$/.test(resourceName)) {
    error('Resource name can only contain letters, numbers, hyphens, and underscores.');
    process.exit(1);
  }

  const target = fs.existsSync('resources')
    ? path.resolve('resources', resourceName)
    : path.resolve(resourceName);

  if (fs.existsSync(target)) {
    error(`Directory "${target}" already exists.`);
    process.exit(1);
  }

  log(`  ${c.bold}Creating resource:${c.reset} ${target}`);
  log('');

  try {
    fs.mkdirSync(target, { recursive: true });

    // fxmanifest.lua
    fs.writeFileSync(path.join(target, 'fxmanifest.lua'), `fx_version 'cerulean'
game 'common'

name '${resourceName}'
version '1.0.0'
description 'A FiveM resource using OrvexORM'

dependency 'oxmysql'
dependency 'orvexorm'

server_scripts {
    '@orvexorm/lib/import.lua',
    'server/main.lua',
}
`);

    // server/main.lua
    fs.mkdirSync(path.join(target, 'server'), { recursive: true });
    fs.writeFileSync(path.join(target, 'server', 'main.lua'), `-- ${resourceName} — powered by OrvexORM
local ORM = OrvexORM

-- Define your models
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- Auto-create the table
User.sync()

-- Example: Save player on connect
AddEventHandler("playerConnecting", function(name, _, deferrals)
    local src = source
    local identifier = GetPlayerIdentifierByType(src, "license")

    if identifier then
        User.findOrCreate(
            { identifier = identifier },
            { money = 500, job = "unemployed" }
        )
    end
end)

print("^2[${resourceName}]^0 loaded with OrvexORM")
`);
  } catch (err) {
    if (err.code === 'EACCES' || err.code === 'EPERM') {
      error(`Permission denied writing to "${target}".`);
    } else {
      error(`Failed to create resource: ${err.message}`);
    }
    process.exit(1);
  }

  success(`Resource created at ${c.bold}${target}${c.reset}`);
  log('');
  log(`  ${c.bold}Files created:${c.reset}`);
  log(`    ${c.dim}${target}/fxmanifest.lua${c.reset}`);
  log(`    ${c.dim}${target}/server/main.lua${c.reset}`);
  log('');
  log(`  ${c.bold}Next:${c.reset}`);
  log(`    1. Make sure ${c.cyan}orvexorm${c.reset} is installed (npx orvexorm install)`);
  log(`    2. Add ${c.cyan}ensure ${resourceName}${c.reset} to server.cfg`);
  log(`    3. Edit ${c.cyan}server/main.lua${c.reset} to add your logic`);
  log('');
}

// Parse command
const args = process.argv.slice(2);
const command = args[0] || 'help';

switch (command) {
  case 'install':
  case 'i':
    install(args[1]);
    break;
  case 'update':
  case 'u':
    update(args[1]);
    break;
  case 'init':
  case 'create':
  case 'new':
    init(args[1]);
    break;
  case 'version':
  case '-v':
  case '--version':
    log(`orvexorm v${VERSION}`);
    break;
  case 'help':
  case '-h':
  case '--help':
  default:
    help();
    break;
}
