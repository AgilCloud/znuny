## Resumo

-

## Riscos

- [ ] Baixo risco, mudança isolada e reversível
- [ ] Altera build, imagem Docker ou Compose
- [ ] Altera configuração, variáveis de ambiente ou secrets
- [ ] Altera inicialização, healthcheck ou comportamento em runtime
- [ ] Pode afetar compatibilidade, migração ou dados persistidos

## Testes

- [ ] `docker compose config`
- [ ] `hadolint docker/Dockerfile`
- [ ] `docker build` local ou CI sem push
- [ ] Smoke test de inicialização/healthcheck com Compose
- [ ] Testes manuais relevantes descritos abaixo
- [ ] Não se aplica; justificativa abaixo

## Segurança

- [ ] Não adiciona secrets, tokens ou credenciais ao repositório
- [ ] Usa secrets temporários/locais para testes quando necessário
- [ ] Validei permissões, portas expostas e variáveis sensíveis
- [ ] Dependências ou imagens base foram avaliadas quando alteradas

## Documentação

- [ ] README, exemplos ou runbooks atualizados
- [ ] Variáveis de ambiente novas/alteradas documentadas
- [ ] Mudança sem impacto de documentação

## Observações

-
