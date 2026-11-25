-- =====================================================================
-- Sistema de Gestao para Clinica Medica
-- Testes negativos de integridade referencial e de chaves
-- Entregavel da Semana 15 - Parte 3 (Bonus)
-- =====================================================================
-- Execucao (depois do 02_insercao_teste.sql):
--   psql -U postgres -d clinica_medica -f database/03_testes_integridade.sql
--
-- Todos os comandos abaixo DEVEM falhar. Cada teste roda dentro do seu
-- proprio bloco de transacao, encerrado por ROLLBACK, para que uma falha
-- nao interrompa o teste seguinte e nada seja gravado no banco.
-- =====================================================================

\set ON_ERROR_STOP off

\echo ''
\echo '=== TESTE 1: FK inexistente - consulta para paciente que nao existe ==='
BEGIN;
INSERT INTO consultas (paciente_id, medico_id, especialidade_id, data_hora)
VALUES (9999, 1, 1, '2026-12-15 08:00-03');
ROLLBACK;

\echo ''
\echo '=== TESTE 2: PK duplicada - mesmo par (medico, especialidade) ==='
BEGIN;
INSERT INTO medicos_especialidades (medico_id, especialidade_id) VALUES (1, 1);
ROLLBACK;

\echo ''
\echo '=== TESTE 3: UNIQUE violado - dois pacientes com o mesmo CPF ==='
BEGIN;
INSERT INTO pacientes
    (nome, cpf, data_nascimento, cep, logradouro, numero, bairro, cidade_id)
VALUES ('Clone da Mariana', '52998224725', '1990-01-01',
        '60150160', 'Rua Teste', '10', 'Centro', 1);
ROLLBACK;

\echo ''
\echo '=== TESTE 4: FK composta - especialidade que o medico nao possui ==='
-- O Dr. Rafael (medico_id 2) e ortopedista; nao pode atender como cardiologista.
BEGIN;
INSERT INTO consultas (paciente_id, medico_id, especialidade_id, data_hora)
VALUES (1, 2, 1, '2026-12-16 08:00-03');
ROLLBACK;

\echo ''
\echo '=== TESTE 5: ON DELETE RESTRICT - apagar paciente com historico ==='
BEGIN;
DELETE FROM pacientes WHERE paciente_id = 1;
ROLLBACK;

\echo ''
\echo '=== TESTE 6: 1:1 violado - segundo pagamento para a mesma consulta ==='
BEGIN;
INSERT INTO pagamentos (consulta_id, valor, forma) VALUES (1, 100.00, 'pix');
ROLLBACK;

\echo ''
\echo '=== TESTE 7: CHECK - pagamento com valor negativo ==='
BEGIN;
INSERT INTO pagamentos (consulta_id, valor, forma) VALUES (3, -50.00, 'dinheiro');
ROLLBACK;

\echo ''
\echo '=== TESTE 8: indice unico parcial - dois agendamentos ativos no mesmo horario ==='
BEGIN;
INSERT INTO consultas (paciente_id, medico_id, especialidade_id, data_hora, situacao)
VALUES (3, 1, 1, '2026-11-10 09:00-03', 'agendada');
ROLLBACK;

\echo ''
\echo '=== CONTROLE: o banco continua consistente apos os 8 testes ==='
SELECT
    (SELECT count(*) FROM pacientes)              AS pacientes,
    (SELECT count(*) FROM consultas)              AS consultas,
    (SELECT count(*) FROM pagamentos)             AS pagamentos,
    (SELECT count(*) FROM medicos_especialidades) AS medicos_especialidades;
