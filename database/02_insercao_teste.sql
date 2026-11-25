-- =====================================================================
-- Sistema de Gestao para Clinica Medica
-- Insercao de dados de teste (DML)
-- Entregavel da Semana 15 - Parte 3 (Tarefa de Casa)
-- =====================================================================
-- Execucao (depois do 01_ddl.sql):
--   psql -U postgres -d clinica_medica -f database/02_insercao_teste.sql
--
-- Objetivo: povoar tabelas relacionadas para comprovar que as chaves
-- estrangeiras estao ativas e que os relacionamentos se sustentam.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Tabelas de apoio (lado "1" dos relacionamentos)
-- ---------------------------------------------------------------------

INSERT INTO cidades (nome, uf) VALUES
    ('Fortaleza', 'CE'),
    ('Caucaia',   'CE'),
    ('Sao Paulo', 'SP');

INSERT INTO convenios (nome, registro_ans) VALUES
    ('Unimed Ceara',  '301001'),
    ('Hapvida Saude', '368253');

INSERT INTO especialidades (nome) VALUES
    ('Cardiologia'),
    ('Ortopedia'),
    ('Clinica Medica'),
    ('Psiquiatria');

INSERT INTO procedimentos (codigo_tuss, nome, valor_tabela) VALUES
    ('10101012', 'Consulta em consultorio',            250.00),
    ('40101010', 'Eletrocardiograma convencional',      90.00),
    ('40808014', 'Radiografia de joelho',              120.00),
    ('20103026', 'Infiltracao articular',              380.00);

-- ---------------------------------------------------------------------
-- PACIENTES  (FK para convenios e cidades)
-- ---------------------------------------------------------------------

INSERT INTO pacientes
    (nome, cpf, data_nascimento, email, convenio_id, numero_carteirinha,
     cep, logradouro, numero, complemento, bairro, cidade_id)
VALUES
    ('Mariana Alves Rocha', '52998224725', '1988-04-12', 'mariana.rocha@email.com',
     1, '0012345678', '60150160', 'Avenida Santos Dumont', '1800', 'Sala 4', 'Aldeota', 1),

    ('Joao Pedro Lima',     '11144477735', '1975-11-30', 'jp.lima@email.com',
     2, '0098765432', '60510000', 'Rua Padre Guerra', '420', NULL, 'Parquelandia', 1),

    ('Beatriz Souza Matos', '39053344705', '1996-02-19', NULL,
     NULL, NULL, '61650230', 'Rua Icarai', '95', 'Apto 302', 'Jurema', 2);

-- ---------------------------------------------------------------------
-- TELEFONES  (1FN: um telefone por linha, nunca "9999, 8888" na mesma celula)
-- ---------------------------------------------------------------------

INSERT INTO telefones_paciente (paciente_id, tipo, numero) VALUES
    (1, 'celular',     '85988776655'),
    (1, 'comercial',   '8532334455'),
    (2, 'celular',     '85991112233'),
    (3, 'celular',     '85987654321'),
    (3, 'residencial', '8532001122');

-- ---------------------------------------------------------------------
-- MEDICOS e a tabela associativa N:N
-- ---------------------------------------------------------------------

INSERT INTO medicos (nome, crm, uf_crm, email) VALUES
    ('Dra. Helena Castro',  '14523', 'CE', 'helena.castro@clinica.com'),
    ('Dr. Rafael Monteiro', '20871', 'CE', 'rafael.monteiro@clinica.com');

-- Um medico pode ter mais de uma especialidade: o N:N em acao.
INSERT INTO medicos_especialidades (medico_id, especialidade_id, rqe, principal) VALUES
    (1, 1, '12345', TRUE),   -- Helena  / Cardiologia (principal)
    (1, 3, NULL,    FALSE),  -- Helena  / Clinica Medica
    (2, 2, '67890', TRUE);   -- Rafael  / Ortopedia

-- ---------------------------------------------------------------------
-- CONSULTAS  (FK para pacientes, medicos e para o par medico+especialidade)
-- ---------------------------------------------------------------------

INSERT INTO consultas (paciente_id, medico_id, especialidade_id, data_hora, situacao, observacoes) VALUES
    (1, 1, 1, '2026-11-10 09:00-03', 'realizada', 'Retorno com exame de ECG.'),
    (2, 2, 2, '2026-11-12 14:30-03', 'realizada', 'Dor no joelho direito ha 3 semanas.'),
    (3, 1, 3, '2026-12-02 10:00-03', 'agendada',  NULL);

-- ---------------------------------------------------------------------
-- CONSULTAS_PROCEDIMENTOS  (N:N resolvido, PK composta)
-- ---------------------------------------------------------------------

INSERT INTO consultas_procedimentos (consulta_id, procedimento_id, quantidade, valor_cobrado) VALUES
    (1, 1, 1, 250.00),
    (1, 2, 1,  90.00),
    (2, 1, 1, 250.00),
    (2, 3, 2, 110.00);   -- valor negociado abaixo da tabela: depende do par

-- ---------------------------------------------------------------------
-- PAGAMENTOS  (1:1 com consulta)
-- ---------------------------------------------------------------------

INSERT INTO pagamentos (consulta_id, valor, forma) VALUES
    (1, 340.00, 'convenio'),
    (2, 470.00, 'pix');

COMMIT;

-- ---------------------------------------------------------------------
-- Conferencia dos relacionamentos
-- ---------------------------------------------------------------------

\echo ''
\echo '--- Historico do paciente (RF07): consulta atravessa 5 tabelas ---'
SELECT p.nome            AS paciente,
       m.nome            AS medico,
       e.nome            AS especialidade,
       c.data_hora,
       c.situacao,
       f.valor_total
  FROM consultas c
  JOIN pacientes      p ON p.paciente_id      = c.paciente_id
  JOIN medicos        m ON m.medico_id        = c.medico_id
  JOIN especialidades e ON e.especialidade_id = c.especialidade_id
  JOIN vw_faturamento_consulta f ON f.consulta_id = c.consulta_id
 ORDER BY c.data_hora;

\echo ''
\echo '--- Telefones por paciente (1FN) ---'
SELECT p.nome, t.tipo, t.numero
  FROM pacientes p
  JOIN telefones_paciente t ON t.paciente_id = p.paciente_id
 ORDER BY p.nome, t.tipo;

\echo ''
\echo '--- Especialidades por medico (N:N) ---'
SELECT m.nome AS medico, e.nome AS especialidade, me.rqe, me.principal
  FROM medicos m
  JOIN medicos_especialidades me ON me.medico_id = m.medico_id
  JOIN especialidades e          ON e.especialidade_id = me.especialidade_id
 ORDER BY m.nome, me.principal DESC;
