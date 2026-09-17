# CLAUDE.md

Diretivas de trabalho neste repositório. Leia antes de alterar código.

## O que é este repositório

`pgAdminEx` é um fork de trabalho de **pgAdmin 4** (https://github.com/pgadmin-org/pgadmin4),
mantido por Hermes Silva em https://github.com/HermesSilva/pgAdminEx. A versão corrente
acompanha o upstream (ver `web/version.py`: `APP_RELEASE` / `APP_REVISION`).

O fork é um **espelho com correções**: a intenção é que cada mudança volte ao upstream como
Pull Request. Isso determina quase tudo abaixo.

**Consequências práticas:**

- Escreva o código como o upstream escreveria. O objetivo não é "meu jeito", é um patch que
  um mantenedor do pgAdmin aceite sem reescrever.
- Nada de rebranding, nada de renomear `pgadmin` para `pgadminex`, nada de mexer em
  `web/branding.py` ou no copyright. O nome do fork é do repositório, não do produto.
- Commits pequenos e temáticos, rebaseáveis. Um commit que mistura fix + refactor não
  sobrevive a um merge do upstream.
- Antes de começar uma correção, verifique se o upstream já a fez (`git log`, issues do
  pgadmin-org). Duplicar trabalho no fork custa conflito depois.

## Foco do trabalho

Em ordem de peso, as frentes ativas são:

1. **Segurança / hardening** — foi o grosso do 9.18 (CVE-2026-86861..86864: bypass de
   autenticação no modo webserver, injeção de argumento/connection-string em Backup,
   Restore e Maintenance, TOCTOU no File Manager). Veja "Segurança" abaixo.
2. **Novas features** — nós do Object Explorer, ferramentas, telas React.
3. **Performance e build** — tempo e tamanho de bundle, imports diferidos
   (cf. `perf: defer the cloud SDK imports`), empacotamento em `pkg/`.

## Arquitetura, em uma tela

| Caminho | O que é |
|---|---|
| `web/pgadmin/` | Aplicação Flask + React. Coração do projeto. |
| `web/pgadmin/browser/server_groups/servers/` | Nós do Object Explorer (databases, roles, tablespaces, pgagent…). Cada nó = módulo Python + SQL em `templates/` + JS. |
| `web/pgadmin/tools/` | Ferramentas: backup, restore, maintenance, sqleditor, erd, schema_diff, debugger, psql, import_export… |
| `web/pgadmin/model/` | Modelo SQLAlchemy do banco de configuração (SQLite ou Postgres). |
| `web/migrations/` | Migrações Alembic do banco de configuração. |
| `web/regression/` | Suíte de testes Python (API, re_sql, feature_tests com Selenium). |
| `runtime/` | Aplicação Electron que hospeda o servidor Python no modo desktop. |
| `pkg/` | Empacotamento: win32, mac, debian, redhat, docker, helm, pip, src. |
| `docs/en_US/` | Documentação Sphinx, incluindo as release notes. |
| `tools/` | Utilitários de desenvolvimento e build. |

O SQL dos nós vive em `templates/<nó>/sql/<versão-do-servidor>/*.sql`, selecionado por
versão do PostgreSQL. Ao alterar SQL de um nó, verifique **todas** as pastas de versão —
elas não herdam umas das outras automaticamente.

## Shell nesta máquina

O padrão é **PowerShell 7.6.6**, projeto em `D:\Tootega\Source\pgAdminEx`, temp em
`$env:TEMP`, sem heredoc. Git Bash (`/d/Tootega/Source/pgAdminEx`) e WSL
(`/mnt/d/Tootega/Source/pgAdminEx`) existem e devem ser escolhidos explicitamente quando a
tarefa exigir POSIX ou Linux real. Nunca cruze sintaxe de um shell com caminhos de outro.

O `Makefile` assume `/bin/sh` e não roda no PowerShell. No Windows use os comandos diretos:

```powershell
cd web; yarn install          # equivale a: make install-node
cd web; yarn run bundle       # equivale a: make bundle
cd web; yarn run linter       # ESLint
cd web; yarn run test:js-once # Jest
pycodestyle --config=.pycodestyle web/   # equivale a: make check-pep8
cd web; python regression/runtests.py --exclude feature_tests
```

## Estilo de código

**Python** — pycodestyle com `.pycodestyle` na raiz: **máximo 79 colunas**, ignorando
E402, W504, E231. Essa é a regra que mais quebra CI em patch novo; conte as colunas.
Cabeçalho de copyright em todo arquivo novo, copiado de um arquivo vizinho.

**JavaScript/React** — ESLint com `web/.eslintrc.js` (flat config, React + Jest +
TypeScript). Componentes funcionais com hooks; siga o arquivo vizinho, não um padrão de
outro projeto. Mesmo cabeçalho de copyright.

**Geral** — a documentação de contribuição do upstream vale aqui:
`docs/en_US/coding_standards.rst`, `code_overview.rst`, `code_review.rst`, e o
`CONTRIBUTING.md` da raiz.

## Testes

- Python: `web/regression/runtests.py`. Testes de API ficam em `tests/` dentro do módulo
  correspondente (ex.: `web/pgadmin/tools/backup/tests/`). Exclua `feature_tests` no ciclo
  rápido — eles exigem Selenium e um servidor de verdade.
- SQL por versão: `web/regression/re_sql/`.
- JavaScript: Jest, colocado ao lado do código.
- **Toda correção de segurança precisa de um teste de regressão** que falhe sem o fix.
  Foi assim em todos os CVEs do 9.18, e é o que impede a regressão silenciosa.

## Segurança

Este é um cliente de banco de dados que executa binários externos com credenciais do
usuário. Os padrões de falha já vistos aqui, e que devem ser assumidos como recorrentes:

- **Injeção de argumento**: valor controlado pelo cliente entrando no argv de `pg_dump`,
  `pg_restore`, `psql`. `getopt_long` permuta argumentos, então um valor iniciado por `-`
  vira uma opção. Não passe valores do cliente como argumento posicional.
- **Injeção de connection-string**: libpq expande um nome de banco contendo `=` em uma
  connection string completa, sobrescrevendo `--host`/`--port` e vazando a senha de
  `PGPASSWORD`. A correção adotada é passar o banco via **`PGDATABASE`**, que libpq nunca
  expande — e rejeitar banco vazio/ausente, senão o valor cai de volta no nome do papel.
- **TOCTOU de caminho**: validar o caminho e depois abrir com `open()` permite plantar um
  symlink no meio. Valide e abra atomicamente.
- **Identidade vinda de cabeçalho HTTP**: nunca confiar sem proxy declarado e segredo.
- **XSS** em tudo que é renderizado a partir de dados do servidor.

Ao tocar em `tools/backup`, `tools/restore`, `tools/maintenance`, `misc/file_manager`,
`authenticate/` ou qualquer ponto que monte argv: presuma hostilidade do input e escreva o
teste de regressão primeiro.

## Armadilha: bundle de desenvolvimento e CSP

Desde o 9.18 (`fb0ca5c4c`) o pgAdmin serve uma CSP com nonce por requisição e **sem
`unsafe-eval`**. O webpack, sem `NODE_ENV=production`, escolhe o devtool `'eval'`
(`web/webpack.config.js:39`) — e o navegador bloqueia tudo.

O sintoma engana: **página em branco, com todos os assets retornando HTTP 200** e
nenhum erro no log do servidor. O erro só existe no console do navegador.

Duas saídas, ambas válidas:

- `NODE_ENV=production` ao gerar o bundle. É o que `dev-run.cmd` e o script `bundle`
  do `package.json` fazem.
- `DEBUG = True` no `config_local.py`: `get_content_security_policy()`
  (`web/pgadmin/utils/security_headers.py:56`) acrescenta `'unsafe-eval'` sozinho
  nesse caso. É a saída prevista pelo upstream para quem quer bundle de
  desenvolvimento com source maps legíveis.

## Release notes

Toda mudança visível ao usuário entra em `docs/en_US/release_notes_<X>_<Y>.rst`, na seção
certa (New features / Housekeeping / Bug fixes), **com a issue do pgadmin-org citada** —
esse é o formato do arquivo e foi corrigido explicitamente para tal. Entrada de segurança
cita o CVE e credita quem reportou.

## Git

- Branch principal: `master`. Trabalhe em branch temática quando a mudança for maior que
  um commit.
- Mensagens no padrão já usado aqui: `fix(restore, maintenance): ...`,
  `test(backup): ...`, `perf: ...`, `chore(deps): ...`, `docs: ...`.
- Commit ou push **somente quando solicitado**.
- Rode `pycodestyle` e o linter JS antes de commitar — o CI em `.github/workflows/` checa
  exatamente isso e falha rápido.

## Ao trabalhar comigo

- Responda em **português**; código, identificadores e mensagens de commit permanecem em
  inglês, como o restante do repositório.
- Prefira ler o arquivo vizinho a inventar um padrão. Este repositório tem convenções
  fortes e antigas; consistência vale mais que elegância.
- Não faça refactor oportunista junto de um fix. Se algo ao lado está ruim, aponte e
  pergunte.
