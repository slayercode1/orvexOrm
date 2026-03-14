import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'category',
      label: 'Pour commencer',
      collapsed: false,
      items: [
        'introduction',
        'installation',
        'getting-started',
        'auto-completion',
      ],
    },
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'guides/models',
        'guides/crud',
        'guides/query-builder',
        'guides/relations',
        'guides/aggregates',
        'guides/validation',
        'guides/transactions',
        'guides/cache',
        'guides/json-columns',
        'guides/migrations',
      ],
    },
    {
      type: 'category',
      label: 'Reference API',
      collapsed: false,
      items: [
        'api/orm',
        'api/model',
        'api/instance',
        'api/builder',
      ],
    },
    'examples',
  ],
};

export default sidebars;
