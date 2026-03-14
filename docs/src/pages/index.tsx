import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';
import Translate, {translate} from '@docusaurus/Translate';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <span className={styles.badge}>Open Source &middot; FiveM &middot; oxmysql</span>
        <Heading as="h1" className="hero__title">
          OrvexORM
        </Heading>
        <p className="hero__subtitle">
          <Translate id="homepage.subtitle">
            Un ORM leger pour FiveM. Transforme tes requetes SQL en code Lua lisible.
          </Translate>
        </p>
        <div className={styles.buttons}>
          <Link className={styles.heroButtonPrimary} to="/docs/getting-started">
            <Translate id="homepage.getStarted">Commencer</Translate>
          </Link>
          <Link className={styles.heroButtonSecondary} to="/docs/examples">
            <Translate id="homepage.examples">Exemples</Translate>
          </Link>
        </div>
      </div>
    </header>
  );
}

function Features() {
  const features = [
    {
      title: translate({id: 'homepage.feature.crud.title', message: 'CRUD'}),
      desc: translate({id: 'homepage.feature.crud.desc', message: 'create, find, update, delete — OrvexORM genere le SQL automatiquement.'}),
    },
    {
      title: translate({id: 'homepage.feature.relations.title', message: 'Relations'}),
      desc: translate({id: 'homepage.feature.relations.desc', message: 'hasOne, hasMany, belongsTo, belongsToMany avec attach/detach.'}),
    },
    {
      title: translate({id: 'homepage.feature.queryBuilder.title', message: 'Query Builder'}),
      desc: translate({id: 'homepage.feature.queryBuilder.desc', message: 'Chainable. WHERE, LIKE, IN, BETWEEN, JOIN, GROUP BY, ORDER BY.'}),
    },
    {
      title: translate({id: 'homepage.feature.migrations.title', message: 'Migrations'}),
      desc: translate({id: 'homepage.feature.migrations.desc', message: 'Cree tes tables avec sync() ou des migrations versionnees.'}),
    },
    {
      title: translate({id: 'homepage.feature.cache.title', message: 'Cache'}),
      desc: translate({id: 'homepage.feature.cache.desc', message: 'Cache TTL integre avec invalidation automatique sur les ecritures.'}),
    },
    {
      title: translate({id: 'homepage.feature.json.title', message: 'JSON'}),
      desc: translate({id: 'homepage.feature.json.desc', message: 'Colonnes JSON et auto-detection. Tables Lua converties automatiquement.'}),
    },
  ];

  return (
    <section className={styles.features}>
      <div className="container">
        <Heading as="h2" className={styles.sectionTitle}>
          <Translate id="homepage.features.title">Fonctionnalites</Translate>
        </Heading>
        <p className={styles.sectionSubtitle}>
          <Translate id="homepage.features.subtitle">
            Tout ce dont tu as besoin pour gerer ta base de donnees sur FiveM.
          </Translate>
        </p>
        <div className="row">
          {features.map((f, i) => (
            <div key={i} className="col col--4 margin-bottom--md">
              <div className={styles.featureCard}>
                <div className={styles.featureTitle}>{f.title}</div>
                <p className={styles.featureDesc}>{f.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

const codeLeft = `local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    position   = "json",
}, { primaryKey = "identifier" })

User.sync()

local player = User.create({
    identifier = "license:abc",
    money      = 500,
    job        = "unemployed",
    position   = { x = 0, y = 0, z = 0 },
})`;

const codeRight = `local richCops = User.query()
    :where({ job = "police" })
    :where("money", ">", 1000)
    :orderBy("money", "DESC")
    :limit(10)
    :get()

local avgMoney = User.avg("money")
local totalCops = User.count({ job = "police" })

User.hasMany("vehicles", Vehicle, {
    foreignKey = "owner"
})

local cars = player:get("vehicles")`;

function CodeShowcase() {
  return (
    <section className={styles.codeShowcase}>
      <div className="container">
        <div className="row">
          <div className="col col--6">
            <span className={styles.codeTag}>
              <Translate id="homepage.code.models.tag">MODELES</Translate>
            </span>
            <Heading as="h3" className={styles.codeShowcaseTitle}>
              <Translate id="homepage.code.models.title">Definis, cree, utilise</Translate>
            </Heading>
            <p className={styles.codeShowcaseSubtitle}>
              <Translate id="homepage.code.models.subtitle">
                Un modele = une table. Le SQL est genere automatiquement.
              </Translate>
            </p>
            <CodeBlock language="lua">{codeLeft}</CodeBlock>
          </div>
          <div className="col col--6">
            <span className={styles.codeTag}>
              <Translate id="homepage.code.queries.tag">REQUETES</Translate>
            </span>
            <Heading as="h3" className={styles.codeShowcaseTitle}>
              <Translate id="homepage.code.queries.title">Query builder chainable</Translate>
            </Heading>
            <p className={styles.codeShowcaseSubtitle}>
              <Translate id="homepage.code.queries.subtitle">
                Filtres, tri, pagination, jointures, aggregations, relations.
              </Translate>
            </p>
            <CodeBlock language="lua">{codeRight}</CodeBlock>
          </div>
        </div>
      </div>
    </section>
  );
}

function QuickStart() {
  const paths = [
    {
      num: '1',
      title: translate({id: 'homepage.path.install.title', message: 'Installation'}),
      desc: translate({id: 'homepage.path.install.desc', message: 'Configure OrvexORM dans ton serveur FiveM.'}),
      link: '/docs/installation',
    },
    {
      num: '2',
      title: translate({id: 'homepage.path.start.title', message: 'Premier pas'}),
      desc: translate({id: 'homepage.path.start.desc', message: 'Les bases : modeles, CRUD, premier joueur.'}),
      link: '/docs/getting-started',
    },
    {
      num: '3',
      title: translate({id: 'homepage.path.guides.title', message: 'Guides'}),
      desc: translate({id: 'homepage.path.guides.desc', message: 'Query builder, relations, migrations, cache.'}),
      link: '/docs/guides/models',
    },
    {
      num: '4',
      title: translate({id: 'homepage.path.api.title', message: 'API'}),
      desc: translate({id: 'homepage.path.api.desc', message: 'Reference complete de chaque methode.'}),
      link: '/docs/api/orm',
    },
  ];

  return (
    <section className={styles.quickStart}>
      <div className="container">
        <Heading as="h2" className={styles.quickStartTitle}>
          <Translate id="homepage.quickstart.title">Documentation</Translate>
        </Heading>
        <p className={styles.quickStartSubtitle}>
          <Translate id="homepage.quickstart.subtitle">Choisis ton point de depart.</Translate>
        </p>
        <div className="row">
          {paths.map((p, i) => (
            <div key={i} className="col col--3 margin-bottom--md">
              <Link to={p.link} className={styles.pathCard}>
                <span className={styles.pathNumber}>{p.num}</span>
                <div className={styles.pathTitle}>{p.title}</div>
                <p className={styles.pathDesc}>{p.desc}</p>
                <span className={styles.pathArrow}>&rarr;</span>
              </Link>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title={translate({id: 'homepage.layout.title', message: 'ORM pour FiveM'})}
      description={translate({id: 'homepage.layout.description', message: 'OrvexORM — un ORM leger pour FiveM construit sur oxmysql'})}>
      <HomepageHeader />
      <main>
        <Features />
        <CodeShowcase />
        <QuickStart />
      </main>
    </Layout>
  );
}
