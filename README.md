# Znuny LTS em Docker

[![CI](https://github.com/agilcloud/znuny/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/agilcloud/znuny/actions/workflows/ci.yaml)
[![CD](https://github.com/agilcloud/znuny/actions/workflows/cd.yaml/badge.svg?branch=main)](https://github.com/agilcloud/znuny/actions/workflows/cd.yaml)
[![Docker pulls](https://img.shields.io/docker/pulls/agilcloud/znuny?logo=docker&label=Docker%20pulls)](https://hub.docker.com/r/agilcloud/znuny)
[![Docker image version](https://img.shields.io/docker/v/agilcloud/znuny?sort=semver&logo=docker&label=Docker%20Hub)](https://hub.docker.com/r/agilcloud/znuny/tags)
[![License: GPL/AGPL](https://img.shields.io/badge/license-GPL%2FAGPL-blue)](#licencas-gplagpl)
[![Non-root runtime](https://img.shields.io/badge/runtime-non--root%20UID%2010001-success)](docker/Dockerfile)
[![SBOM and provenance](https://img.shields.io/badge/SBOM%20%26%20provenance-enabled-success)](.github/workflows/cd.yaml)

Documentacao operacional, em portugues brasileiro, para construir, executar,
publicar e manter uma imagem Docker/Compose do Znuny LTS.

Este projeto deve empacotar o Znuny LTS de forma reprodutivel, com versionamento
explicito do artefato upstream, persistencia de dados fora do container e fluxo
de entrega compativel com GitHub Flow.

## Sumario

- [Objetivo](#objetivo)
- [Decisao de versao e integridade](#decisao-de-versao-e-integridade)
- [Pre-requisitos](#pre-requisitos)
- [Setup do `.env`](#setup-do-env)
- [Credenciais iniciais](#credenciais-iniciais)
- [Variaveis de ambiente](#variaveis-de-ambiente)
- [Secrets](#secrets)
- [Build local](#build-local)
- [Execucao local com Docker Compose](#execucao-local-com-docker-compose)
- [Volumes e persistencia](#volumes-e-persistencia)
- [Healthchecks](#healthchecks)
- [Backup](#backup)
- [Restore](#restore)
- [Upgrade de versao](#upgrade-de-versao)
- [Troubleshooting](#troubleshooting)
- [Publicacao no Docker Hub](#publicacao-no-docker-hub)
- [GitHub Flow, branch protection e PRs](#github-flow-branch-protection-e-prs)
- [Conventional Commits](#conventional-commits)
- [Licencas GPL/AGPL](#licencas-gplagpl)

## Objetivo

A imagem deve fornecer uma instalacao conteinerizada do Znuny LTS para uso local,
homologacao e publicacao em registry. O Compose deve orquestrar pelo menos:

- aplicacao Znuny;
- banco de dados PostgreSQL;
- volumes persistentes para dados da aplicacao e do banco;
- secrets para credenciais sensiveis;
- healthchecks para facilitar diagnostico e automacao.

O nome do repositorio Docker Hub deve ser parametrizavel pela variavel
`DOCKERHUB_REPOSITORY`. Quando nao informado, use como referencia:

```text
agilcloud/znuny
```

Link parametrizavel:

```text
https://hub.docker.com/r/${DOCKERHUB_REPOSITORY:-agilcloud/znuny}
```

## Decisao de versao e integridade

Use o artefato versionado do Znuny:

```text
znuny-7.1.6.tar.gz
```

A imagem deve validar o download com o SHA256 oficial publicado pelo projeto
Znuny. Essa decisao e intencional: aliases como `latest-7.1` podem avancar para
outro release patch sem mudanca no Dockerfile, tornando builds futuros
diferentes de builds antigos.

Padrao recomendado:

```dockerfile
ARG ZNUNY_VERSION=7.1.6
ARG ZNUNY_PACKAGE=znuny-${ZNUNY_VERSION}.tar.gz
ARG ZNUNY_SHA256=<sha256-oficial-do-znuny-7.1.6.tar.gz>
```

O valor de `ZNUNY_SHA256` deve vir da fonte oficial do Znuny para a versao
exata. Ao atualizar de versao, atualize juntos `ZNUNY_VERSION`, `ZNUNY_PACKAGE`
e `ZNUNY_SHA256`.

## Pre-requisitos

- Docker Engine recente.
- Docker Compose v2 (`docker compose`, sem hifen).
- Git.
- GitHub CLI (`gh`) para abrir pull requests.
- Conta no Docker Hub com permissao de push no repositorio configurado.

Verificacao rapida:

```bash
docker version
docker compose version
git --version
gh --version
```

## Setup do `.env`

Crie um arquivo `.env` na raiz do repositorio a partir do exemplo abaixo.
Nao commite `.env` com credenciais reais.

O caminho mais simples e usar o alvo ja preparado:

```bash
make env
```

Esse comando cria `.env` e secrets locais em `.secrets/` sem sobrescrever um
arquivo `.env` existente.

Exemplo de `.env`:

```dotenv
COMPOSE_PROJECT_NAME=znuny

# Porta HTTP local.
ZNUNY_HTTP_PORT=8080

# Imagem usada pelo Compose. Para testar o build local, aponte para:
# ZNUNY_IMAGE=agilcloud/znuny:7.1.6
ZNUNY_IMAGE=agilcloud/znuny:7.1.6

# Aplicacao.
ZNUNY_TIMEZONE=America/Bahia
ZNUNY_LANGUAGE=pt_BR
ZNUNY_ADMIN_USER=admin
ZNUNY_ADMIN_EMAIL=admin@localhost
ZNUNY_FQDN=helpdesk.example.com
ZNUNY_HTTPS=false

# Banco PostgreSQL usado pelo Compose.
ZNUNY_DB_TYPE=postgresql
ZNUNY_DB_HOST=db
ZNUNY_DB_PORT=5432
ZNUNY_DB_NAME=znuny
ZNUNY_DB_USER=znuny

# Caminhos dos secrets locais lidos pelo Compose.
ZNUNY_DB_PASSWORD_FILE=.secrets/znuny_db_password
ZNUNY_ADMIN_PASSWORD_FILE=.secrets/znuny_admin_password
```

Crie os secrets locais fora do controle de versao:

```bash
mkdir -p .secrets
printf '%s\n' 'troque-esta-senha-db' > .secrets/znuny_db_password
printf '%s\n' 'troque-esta-senha-admin' > .secrets/znuny_admin_password
chmod 600 .secrets/*
```

Garanta que `.gitignore` ignore:

```gitignore
.env
.secrets/
backups/
```

## Credenciais iniciais

Quando o ambiente e criado com `make env`, o login administrativo inicial e:

```text
Usuario: admin
Senha: conteudo do arquivo .secrets/znuny_admin_password
```

Para visualizar a senha gerada localmente:

```bash
cat .secrets/znuny_admin_password
```

O Znuny tambem cria, pelos SQLs oficiais de instalacao, o usuario
`root@localhost` com senha inicial `root`. Trate essa credencial apenas como
fallback de bootstrap e altere ou desabilite esse acesso antes de usar o
ambiente fora de testes locais.

Para definir outra credencial administrativa antes da primeira subida, edite o
`.env`:

```dotenv
ZNUNY_ADMIN_USER=seu-admin
ZNUNY_ADMIN_EMAIL=seu-admin@localhost
ZNUNY_ADMIN_PASSWORD_FILE=.secrets/znuny_admin_password
```

Depois grave a nova senha no arquivo apontado por `ZNUNY_ADMIN_PASSWORD_FILE`:

```bash
mkdir -p .secrets
openssl rand -base64 32 > .secrets/znuny_admin_password
chmod 600 .secrets/znuny_admin_password
```

Se preferir definir uma senha manual:

```bash
printf '%s\n' 'troque-por-uma-senha-forte' > .secrets/znuny_admin_password
chmod 600 .secrets/znuny_admin_password
```

Para aplicar a troca em uma instalacao ja existente, atualize o `.env` e o
arquivo secret, depois recrie o container da aplicacao:

```bash
docker compose up -d --build --force-recreate znuny
```

O entrypoint le `ZNUNY_ADMIN_USER` e `ZNUNY_ADMIN_PASSWORD_FILE` a cada start:
se o usuario ainda nao existir, ele tenta cria-lo no grupo `admin`; se ja
existir, atualiza a senha para o valor atual do secret.

## Variaveis de ambiente

| Variavel | Obrigatoria | Exemplo | Descricao |
| --- | --- | --- | --- |
| `DOCKERHUB_REPOSITORY` | Sim para publish | `agilcloud/znuny` | Repositorio Docker Hub da imagem. |
| `ZNUNY_IMAGE` | Sim para Compose | `agilcloud/znuny:7.1.6` | Imagem usada pelo servico `znuny`. |
| `ZNUNY_HTTP_PORT` | Nao | `8080` | Porta local exposta para acessar o Znuny. |
| `ZNUNY_TIMEZONE` | Nao | `America/Bahia` | Timezone do container. |
| `ZNUNY_LANGUAGE` | Nao | `pt_BR` | Idioma inicial esperado para a aplicacao. |
| `ZNUNY_ADMIN_USER` | Nao | `admin` | Usuario admin inicial usado pelo bootstrap quando suportado. |
| `ZNUNY_ADMIN_EMAIL` | Nao | `admin@localhost` | E-mail administrativo usado em configuracoes iniciais. Em producao, use um e-mail valido para o seu dominio. |
| `ZNUNY_ADMIN_PASSWORD_FILE` | Sim | `.secrets/znuny_admin_password` | Caminho host do secret admin lido pelo Compose. |
| `ZNUNY_DB_TYPE` | Sim | `postgresql` | Tipo de banco suportado pela imagem. |
| `ZNUNY_DB_HOST` | Sim | `db` | Host do banco no Compose. |
| `ZNUNY_DB_PORT` | Sim | `5432` | Porta do PostgreSQL. |
| `ZNUNY_DB_NAME` | Sim | `znuny` | Nome do banco da aplicacao. |
| `ZNUNY_DB_USER` | Sim | `znuny` | Usuario de aplicacao. |
| `ZNUNY_DB_PASSWORD_FILE` | Sim | `.secrets/znuny_db_password` | Caminho host do secret do banco lido pelo Compose. |
| `ZNUNY_FQDN` | Nao | `helpdesk.example.com` | Nome publico esperado da instalacao. |
| `ZNUNY_HTTPS` | Nao | `false` | Indica se a aplicacao esta atras de HTTPS externo. |

Prefira sempre variaveis `*_FILE` para credenciais. Variaveis com senha em texto
puro podem aparecer em historico de shell, `docker inspect`, logs ou ferramentas
de observabilidade.

## Secrets

No Compose, mapeie secrets como arquivos:

```yaml
secrets:
  znuny_db_password:
    file: ./.secrets/znuny_db_password
  znuny_admin_password:
    file: ./.secrets/znuny_admin_password
```

No Compose, `ZNUNY_DB_PASSWORD_FILE` e `ZNUNY_ADMIN_PASSWORD_FILE` apontam para
arquivos no host. Dentro dos containers, os caminhos devem ser
`/run/secrets/znuny_db_password` e `/run/secrets/znuny_admin_password`. A imagem
local deve consumir esses arquivos via variaveis `*_FILE`; o PostgreSQL usa
`POSTGRES_PASSWORD_FILE`.

Boas praticas:

- nunca commitar secrets;
- usar permissoes restritivas (`chmod 600`);
- trocar secrets apos vazamento ou compartilhamento indevido;
- usar secrets nativos do orquestrador em ambientes produtivos.

## Build local

Build basico:

```bash
make build
```

Build explicito com argumentos:

```bash
docker build \
  --build-arg ZNUNY_VERSION="${ZNUNY_VERSION:-7.1.6}" \
  --build-arg ZNUNY_PACKAGE="znuny-${ZNUNY_VERSION:-7.1.6}.tar.gz" \
  --build-arg ZNUNY_SHA256="${ZNUNY_SHA256}" \
  -t "${DOCKERHUB_REPOSITORY:-agilcloud/znuny}:${IMAGE_TAG:-7.1.6}" \
  -f docker/Dockerfile .
```

Build sem cache, util para validar reproducibilidade:

```bash
docker build --no-cache \
  --build-arg ZNUNY_VERSION="${ZNUNY_VERSION:-7.1.6}" \
  --build-arg ZNUNY_PACKAGE="znuny-${ZNUNY_VERSION:-7.1.6}.tar.gz" \
  --build-arg ZNUNY_SHA256="${ZNUNY_SHA256}" \
  -t "${DOCKERHUB_REPOSITORY:-agilcloud/znuny}:${IMAGE_TAG:-7.1.6}" \
  -f docker/Dockerfile .
```

Inspecione a imagem gerada:

```bash
docker image inspect "${DOCKERHUB_REPOSITORY:-agilcloud/znuny}:${IMAGE_TAG:-7.1.6}"
```

## Execucao local com Docker Compose

Suba os servicos:

```bash
make up
```

Acompanhe logs:

```bash
make logs
```

Acesse localmente:

```text
http://localhost:${ZNUNY_HTTP_PORT:-8080}
```

Verifique containers:

```bash
make ps
```

Pare os servicos mantendo volumes:

```bash
make down
```

Pare e remova volumes locais, somente quando quiser apagar dados:

```bash
docker compose down -v
```

## Volumes e persistencia

Separe dados persistentes da camada imutavel da imagem.

Volumes recomendados:

| Volume | Uso | Observacao |
| --- | --- | --- |
| `znuny_data` | `/opt/znuny/var` | Estado mutavel da aplicacao. |
| `znuny_articles` | `/opt/znuny/var/article` | Artigos, anexos e conteudo de chamados. |
| `znuny_config` | `/opt/znuny/Kernel/Config/Files` | Configuracoes persistentes do Znuny. |
| `postgres_data` | `/var/lib/postgresql/data` | Dados do PostgreSQL. Deve entrar no backup consistente. |

Exemplo Compose:

```yaml
volumes:
  znuny_data:
  znuny_articles:
  znuny_config:
  postgres_data:
```

Evite gravar dados importantes apenas dentro do filesystem efemero do container.
Ao recriar a imagem, tudo que nao estiver em volume pode ser perdido.

## Healthchecks

Use healthchecks para aplicacao e banco.

Exemplo para banco PostgreSQL:

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER}\" -d \"$${POSTGRES_DB}\" -h 127.0.0.1"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 20s
```

Exemplo para web:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/znuny/index.pl >/dev/null || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 90s
```

Comandos de diagnostico:

```bash
make health
docker inspect --format='{{json .State.Health}}' "$(docker compose ps -q znuny)"
```

Se o nome do servico nao for `znuny`, substitua pelo nome real definido no
`docker-compose.yaml`.

## Backup

Faca backup do banco e dos volumes da aplicacao. Antes de restaurar ou fazer
upgrade, gere um backup novo.

Crie o diretorio local:

```bash
mkdir -p backups
```

Backup pelo Makefile:

```bash
make backup
```

Backup logico do banco:

```bash
docker compose exec -T db pg_dump \
  -U "${ZNUNY_DB_USER:-znuny}" \
  "${ZNUNY_DB_NAME:-znuny}" \
  > backups/znuny-db-$(date +%Y%m%d-%H%M%S).sql
```

Backup de volumes:

```bash
docker run --rm \
  -v znuny_znuny_data:/data:ro \
  -v "$PWD/backups:/backup" \
  alpine tar czf /backup/znuny-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

Repita para `znuny_articles`, `znuny_config` e qualquer outro volume persistente
definido no Compose.

Boas praticas:

- validar se o arquivo de backup nao esta vazio;
- armazenar copia fora da maquina local;
- criptografar backups que contenham dados pessoais ou credenciais;
- testar restore periodicamente.

## Restore

Pare a aplicacao antes de restaurar dados:

```bash
docker compose stop znuny
```

Restaure o banco:

```bash
docker compose exec -T db psql \
  -U "${ZNUNY_DB_USER:-znuny}" \
  "${ZNUNY_DB_NAME:-znuny}" \
  < backups/znuny-db-YYYYMMDD-HHMMSS.sql
```

Restaure volume de dados:

```bash
docker run --rm \
  -v znuny_znuny_data:/data \
  -v "$PWD/backups:/backup:ro" \
  alpine sh -lc 'rm -rf /data/* && tar xzf /backup/znuny-data-YYYYMMDD-HHMMSS.tar.gz -C /data'
```

Suba novamente:

```bash
make up
make ps
make logs SERVICE=znuny
```

Depois do restore, valide login, filas, envio/recebimento de e-mail,
permissoes de arquivos e jobs agendados.

## Upgrade de versao

Fluxo recomendado para upgrade:

1. Leia as notas oficiais da versao alvo do Znuny.
2. Crie uma branch de upgrade.
3. Atualize `ZNUNY_VERSION`, `ZNUNY_PACKAGE` e `ZNUNY_SHA256`.
4. Rode build sem cache.
5. Suba um ambiente local com copia de dados ou fixture segura.
6. Execute rotinas oficiais de migracao do Znuny, quando aplicavel.
7. Rode smoke tests manuais: login, abertura de chamado, busca, anexos,
   notificacoes, scheduler e integracao de e-mail.
8. Publique uma tag candidata, por exemplo `7.1.7-rc.1`, antes da tag final se
   o ambiente exigir homologacao.

Exemplo:

```bash
git switch -c codex/upgrade-znuny-7-1-7
docker build --no-cache \
  --build-arg ZNUNY_VERSION=7.1.7 \
  --build-arg ZNUNY_PACKAGE=znuny-7.1.7.tar.gz \
  --build-arg ZNUNY_SHA256="<sha256-oficial-do-znuny-7.1.7.tar.gz>" \
  -t "${DOCKERHUB_REPOSITORY:-agilcloud/znuny}:7.1.7" \
  -f docker/Dockerfile .
make up
make ps
```

Nunca use `latest-7.1` como fonte de build reprodutivel. Esse alias pode mudar
sem que o historico do repositorio mostre qual tarball foi usado em cada imagem.

## Troubleshooting

### Porta local em uso

Sintoma: Compose falha ao publicar a porta.

Acao:

```bash
lsof -iTCP:${ZNUNY_HTTP_PORT:-8080} -sTCP:LISTEN
```

Altere `ZNUNY_HTTP_PORT` no `.env` e suba novamente.

### Banco nao fica saudavel

Verifique logs:

```bash
docker compose logs db
```

Cheque secrets, permissao dos arquivos em `.secrets/` e compatibilidade da
imagem `postgres:16` usada pelo Compose.

### Aplicacao nao conecta no banco

Confirme se `ZNUNY_DB_HOST`, `ZNUNY_DB_NAME`, `ZNUNY_DB_USER` e secrets estao
iguais no servico da aplicacao e no servico do banco.

```bash
docker compose exec znuny env | sort
docker compose exec db psql -U "${ZNUNY_DB_USER:-znuny}" -d "${ZNUNY_DB_NAME:-znuny}" -c '\l'
```

### Permissoes em volumes

Sintoma: erros de escrita, cache ou anexos.

Acao:

```bash
docker compose exec znuny id
docker compose exec znuny ls -la /opt/znuny /var/opt/znuny
```

Alinhe ownership no Dockerfile ou entrypoint. Evite `chmod 777`.

### Checksum falha no build

Sintoma: `sha256sum: WARNING: 1 computed checksum did NOT match`.

Acao:

- confirme se `ZNUNY_VERSION` aponta para `7.1.6`;
- confirme se o arquivo baixado e `znuny-7.1.6.tar.gz`;
- substitua `ZNUNY_SHA256` apenas pelo SHA256 oficial da mesma versao;
- limpe cache de build se necessario com `docker build --no-cache`.

### Container reinicia em loop

Verifique o ultimo erro:

```bash
docker compose logs --tail=200 znuny
docker compose ps
```

Problemas comuns incluem secret ausente, banco indisponivel, permissao de
volume e configuracao inicial incompleta.

## Publicacao no Docker Hub

Defina repositorio e tag:

```bash
export DOCKERHUB_REPOSITORY="${DOCKERHUB_REPOSITORY:-agilcloud/znuny}"
export IMAGE_TAG="${IMAGE_TAG:-7.1.6}"
```

Login:

```bash
docker login
```

Build e push simples:

```bash
docker build \
  --build-arg ZNUNY_VERSION="${ZNUNY_VERSION:-7.1.6}" \
  --build-arg ZNUNY_SHA256="${ZNUNY_SHA256}" \
  -t "${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}" \
  -f docker/Dockerfile .

docker push "${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}"
```

Build multi-arch com Buildx:

```bash
docker buildx create --use --name znuny-builder
docker buildx build \
  --platform "${PLATFORMS:-linux/amd64,linux/arm64}" \
  --build-arg ZNUNY_VERSION="${ZNUNY_VERSION:-7.1.6}" \
  --build-arg ZNUNY_SHA256="${ZNUNY_SHA256}" \
  -t "${DOCKERHUB_REPOSITORY}:${IMAGE_TAG}" \
  -t "${DOCKERHUB_REPOSITORY}:7.1" \
  --push \
  -f docker/Dockerfile .
```

Tags publicadas pelo CD:

- push em `main`: `main` e `sha-<short_sha>`;
- tag `vX.Y.Z`: `X.Y.Z`, `X.Y`, `X` e `latest`.

`latest` e publicado somente em releases versionadas (`vX.Y.Z`). Para ambientes
produtivos, prefira tags versionadas ou digests.

## GitHub Flow, branch protection e PRs

Fluxo de trabalho:

1. Atualize a branch principal local.
2. Crie uma branch curta e descritiva.
3. Faca commits pequenos seguindo Conventional Commits.
4. Abra PR com `gh`.
5. Aguarde CI, review e checks obrigatorios.
6. Faca squash merge ou merge conforme politica do repositorio.

Exemplo:

```bash
git switch main
git pull --ff-only
git switch -c feature/docker-compose-znuny-lts
git status
git add .
git commit -m "feat: add docker compose stack for znuny lts"
gh pr create \
  --base main \
  --head feature/docker-compose-znuny-lts \
  --title "feat: add Docker Compose stack for Znuny LTS" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md
```

Branch protection recomendada para `main`:

- exigir pull request antes de merge;
- exigir pelo menos uma aprovacao;
- exigir status checks do CI;
- exigir branch atualizada antes do merge, se o time preferir fila linear;
- bloquear force push;
- bloquear delecao da branch;
- exigir conversa resolvida antes do merge;
- exigir commits assinados, se a organizacao adotar essa politica;
- restringir quem pode fazer push direto.

Configure a restricao de push direto para permitir merges apenas via PR aprovado
pelos mantenedores `eaojunior` e `eaojunior-agz`. Essa regra e aplicada na
configuracao do repositorio GitHub, nao em arquivos versionados.

## Conventional Commits

Use mensagens no formato:

```text
<tipo>(escopo opcional): <descricao curta>
```

Tipos comuns:

- `docs`: documentacao;
- `feat`: nova funcionalidade;
- `fix`: correcao;
- `build`: build, Dockerfile, Compose ou dependencias de empacotamento;
- `ci`: pipelines;
- `chore`: tarefas de manutencao;
- `refactor`: mudanca interna sem alterar comportamento;
- `test`: testes.

Exemplos:

```text
docs: document docker compose usage for znuny
build: pin znuny tarball checksum
fix: load mysql password from docker secret
ci: add docker image build workflow
```

## Licencas GPL/AGPL

O Znuny e distribuido sob licenca livre da familia GPL/AGPL, conforme a versao e
os componentes upstream. Ao redistribuir uma imagem Docker contendo Znuny:

- preserve avisos de copyright e licenca dos componentes upstream;
- inclua ou aponte para os textos de licenca aplicaveis;
- disponibilize o codigo-fonte correspondente quando a licenca exigir;
- documente alteracoes locais feitas sobre o upstream;
- verifique licencas de pacotes adicionais instalados na imagem;
- nao remova informacoes de autoria do Znuny ou de dependencias.

Para distribuicao publica, mantenha no repositorio um arquivo `LICENSE` com a
licenca aplicavel ao conteudo proprio deste projeto e referencias claras as
licencas upstream do Znuny e dos demais componentes empacotados.

Esta secao nao substitui revisao juridica. Ela registra as obrigacoes tecnicas
minimas que a imagem deve respeitar ao redistribuir software GPL/AGPL.
