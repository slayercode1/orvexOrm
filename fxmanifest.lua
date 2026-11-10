fx_version 'cerulean'
game 'common'
server_only 'yes'

name 'orvexorm'
version '1.3.0'
author 'Orvex'
description 'Lightweight ORM for FiveM built on oxmysql or mysql-async'

server_scripts {
    'utils/helpers.lua',
    'utils/serializer.lua',
    'utils/validator.lua',
    'utils/cache.lua',
    'utils/errors.lua',
    'utils/logger.lua',

    'database/mysql.lua',
    'database/adapter.lua',

    'core/schema.lua',
    'core/query.lua',
    'core/builder.lua',
    'core/relations.lua',
    'core/transaction.lua',
    'core/migration.lua',
    'core/model/hooks.lua',
    'core/model/write.lua',
    'core/model/instance.lua',
    'core/model/querying.lua',
    'core/model/crud.lua',
    'core/model/relations.lua',
    'core/model/nested.lua',
    'core/model.lua',
    'core/orm.lua',

    'lib/export.lua',
    'lib/studio.lua',
}

lua54 'yes'

provide 'orvexorm'
