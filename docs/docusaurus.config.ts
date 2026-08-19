import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'OrvexORM',
  tagline: 'Un ORM simple et puissant pour FiveM',
  favicon: 'img/favicon.ico',

  future: {
    v4: true,
  },

  url: 'https://slayercode1.github.io',
  baseUrl: '/orvexOrm/',

  organizationName: 'slayercode1',
  projectName: 'orvexOrm',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'fr',
    locales: ['fr', 'en'],
    localeConfigs: {
      fr: {
        label: 'Francais',
      },
      en: {
        label: 'English',
      },
    },
  },

  themes: [
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        language: ['fr', 'en'],
        highlightSearchTermsOnTargetPage: true,
        explicitSearchResultPath: true,
        docsRouteBasePath: 'docs',
        indexBlog: false,
      },
    ],
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: 'docs',
          lastVersion: 'current',
          versions: {
            current: {
              label: '1.2.1',
              badge: true,
            },
          },
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.jpg',
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'OrvexORM',
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          type: 'docsVersionDropdown',
          position: 'right',
        },
        {
          type: 'localeDropdown',
          position: 'right',
        },
        {
          href: 'https://github.com/slayercode1/orvexOrm',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Pour commencer',
          items: [
            { label: 'Introduction', to: '/docs/introduction' },
            { label: 'Installation', to: '/docs/installation' },
            { label: 'Premier pas', to: '/docs/getting-started' },
            { label: 'Exemples', to: '/docs/examples' },
          ],
        },
        {
          title: 'Guides',
          items: [
            { label: 'Les Models', to: '/docs/guides/models' },
            { label: 'Query Builder', to: '/docs/guides/query-builder' },
            { label: 'Relations', to: '/docs/guides/relations' },
            { label: 'Migrations', to: '/docs/guides/migrations' },
            { label: 'Studio', to: '/docs/guides/studio' },
          ],
        },
        {
          title: 'Reference API',
          items: [
            { label: 'ORM', to: '/docs/api/orm' },
            { label: 'Model', to: '/docs/api/model' },
            { label: 'Instance', to: '/docs/api/instance' },
            { label: 'Builder', to: '/docs/api/builder' },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} OrvexORM`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['lua'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
