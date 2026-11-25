# Evidências de execução — Parte 3 (Tarefa de Casa)

Saídas reais do PostgreSQL 16 ao executar os três scripts na ordem. Nada aqui foi
digitado à mão: é a cópia do terminal.

```
$ psql -U postgres -c "select version();"
PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0, 64-bit
```

---

## 1. Criação do banco e das tabelas

```
$ psql -U postgres -f database/01_ddl.sql
--- Tabelas criadas ---
                  List of relations
 Schema |          Name           | Type  |  Owner   
--------+-------------------------+-------+----------
 public | cidades                 | table | postgres
 public | consultas               | table | postgres
 public | consultas_procedimentos | table | postgres
 public | convenios               | table | postgres
 public | especialidades          | table | postgres
 public | medicos                 | table | postgres
 public | medicos_especialidades  | table | postgres
 public | pacientes               | table | postgres
 public | pagamentos              | table | postgres
 public | procedimentos           | table | postgres
 public | telefones_paciente      | table | postgres
(11 rows)

```

---

## 2. Inserção de dados de teste em tabelas relacionadas

Os `INSERT` percorrem a cadeia inteira de chaves estrangeiras: `cidades` e
`convenios` antes de `pacientes`; `medicos` e `especialidades` antes da associativa
`medicos_especialidades`; e só então `consultas`, `consultas_procedimentos` e
`pagamentos`. Se alguma FK estivesse inativa ou apontando para o lugar errado, a
carga pararia no meio.

```
$ psql -U postgres -d clinica_medica -f database/02_insercao_teste.sql

--- Historico do paciente (RF07): consulta atravessa 5 tabelas ---
      paciente       |       medico        | especialidade  |       data_hora        | situacao  | valor_total 
---------------------+---------------------+----------------+------------------------+-----------+-------------
 Mariana Alves Rocha | Dra. Helena Castro  | Cardiologia    | 2026-11-10 09:00:00-03 | realizada |      340.00
 Joao Pedro Lima     | Dr. Rafael Monteiro | Ortopedia      | 2026-11-12 14:30:00-03 | realizada |      470.00
 Beatriz Souza Matos | Dra. Helena Castro  | Clinica Medica | 2026-12-02 10:00:00-03 | agendada  |           0
(3 rows)


--- Telefones por paciente (1FN) ---
        nome         |    tipo     |   numero    
---------------------+-------------+-------------
 Beatriz Souza Matos | celular     | 85987654321
 Beatriz Souza Matos | residencial | 8532001122
 Joao Pedro Lima     | celular     | 85991112233
 Mariana Alves Rocha | celular     | 85988776655
 Mariana Alves Rocha | comercial   | 8532334455
(5 rows)


--- Especialidades por medico (N:N) ---
       medico        | especialidade  |  rqe  | principal 
---------------------+----------------+-------+-----------
 Dr. Rafael Monteiro | Ortopedia      | 67890 | t
 Dra. Helena Castro  | Cardiologia    | 12345 | t
 Dra. Helena Castro  | Clinica Medica |       | f
(3 rows)

```

---

## 3. Bônus — testes negativos: violações barradas pelo banco

Os oito comandos abaixo **deveriam falhar**, e falharam. Cada um roda dentro do seu
próprio `BEGIN ... ROLLBACK`, de modo que o erro de um teste não impede o seguinte e
nenhum dado inválido chega a ser gravado.

```
$ psql -U postgres -d clinica_medica -f database/03_testes_integridade.sql

=== TESTE 1: FK inexistente - consulta para paciente que nao existe ===
BEGIN
ERROR:  insert or update on table "consultas" violates foreign key constraint "fk_consultas_paciente"
DETAIL:  Key (paciente_id)=(9999) is not present in table "pacientes".
ROLLBACK

=== TESTE 2: PK duplicada - mesmo par (medico, especialidade) ===
BEGIN
ERROR:  duplicate key value violates unique constraint "pk_medicos_especialidades"
DETAIL:  Key (medico_id, especialidade_id)=(1, 1) already exists.
ROLLBACK

=== TESTE 3: UNIQUE violado - dois pacientes com o mesmo CPF ===
BEGIN
ERROR:  duplicate key value violates unique constraint "uq_pacientes_cpf"
DETAIL:  Key (cpf)=(52998224725) already exists.
ROLLBACK

=== TESTE 4: FK composta - especialidade que o medico nao possui ===
BEGIN
ERROR:  insert or update on table "consultas" violates foreign key constraint "fk_consultas_medico_especialidade"
DETAIL:  Key (medico_id, especialidade_id)=(2, 1) is not present in table "medicos_especialidades".
ROLLBACK

=== TESTE 5: ON DELETE RESTRICT - apagar paciente com historico ===
BEGIN
ERROR:  update or delete on table "pacientes" violates foreign key constraint "fk_consultas_paciente" on table "consultas"
DETAIL:  Key (paciente_id)=(1) is still referenced from table "consultas".
ROLLBACK

=== TESTE 6: 1:1 violado - segundo pagamento para a mesma consulta ===
BEGIN
ERROR:  duplicate key value violates unique constraint "uq_pagamentos_consulta"
DETAIL:  Key (consulta_id)=(1) already exists.
ROLLBACK

=== TESTE 7: CHECK - pagamento com valor negativo ===
BEGIN
ERROR:  new row for relation "pagamentos" violates check constraint "ck_pagamentos_valor_positivo"
DETAIL:  Failing row contains (4, 3, -50.00, dinheiro, 2026-11-25 15:56:37.85308-03).
ROLLBACK

=== TESTE 8: indice unico parcial - dois agendamentos ativos no mesmo horario ===
BEGIN
ERROR:  duplicate key value violates unique constraint "uq_medico_horario"
DETAIL:  Key (medico_id, data_hora)=(1, 2026-11-10 09:00:00-03) already exists.
ROLLBACK

=== CONTROLE: o banco continua consistente apos os 8 testes ===
 pacientes | consultas | pagamentos | medicos_especialidades 
-----------+-----------+------------+------------------------
         3 |         3 |          2 |                      3
(1 row)

```

### Leitura dos resultados

| Teste | Regra testada | Constraint que barrou |
| --- | --- | --- |
| 1 | FK inexistente (integridade referencial) | `fk_consultas_paciente` |
| 2 | PK composta duplicada | `pk_medicos_especialidades` |
| 3 | Chave única duplicada (CPF) | `uq_pacientes_cpf` |
| 4 | FK composta: médico atendendo fora da sua especialidade | `fk_consultas_medico_especialidade` |
| 5 | Exclusão de pai com filho dependente | `ON DELETE RESTRICT` da `fk_consultas_paciente` |
| 6 | Relacionamento 1:1 violado (dois pagamentos) | `uq_pagamentos_consulta` |
| 7 | Regra de negócio: valor negativo | `ck_pagamentos_valor_positivo` |
| 8 | Dois agendamentos ativos no mesmo horário | índice único parcial `uq_medico_horario` |

A última consulta do script confirma que, depois das oito tentativas de violação, as
contagens continuam exatamente como estavam: nenhum registro inválido entrou.
