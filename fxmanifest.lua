fx_version 'cerulean'
game 'common'

name 'orvexorm'
version '1.0.0'
author 'Orvex'
description 'Lightweight ORM for FiveM built on oxmysql or mysql-async'

server_scripts {
    'utils/helpers.lua',
    'utils/serializer.lua',
    'utils/validator.lua',
    'utils/cache.lua',
    'utils/logger.lua',

    'database/mysql_async.lua',
    'database/mysql.lua',
    'database/adapter.lua',

    'core/schema.lua',
    'core/query.lua',
    'core/relations.lua',
    'core/builder.lua',
    'core/transaction.lua',
    'core/migration.lua',
    'core/model.lua',
    'core/orm.lua',

    'lib/export.lua',
}

lua54 'yes'

provide 'orvexorm'
