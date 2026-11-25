-- =====================================================================
-- Sistema de Gestao para Clinica Medica
-- Script DDL do Modelo Logico normalizado (ate a 3FN)
-- Entregavel da Semana 15 - Modelagem Conceitual, Logica e Normalizacao
-- SGBD: PostgreSQL 16
-- =====================================================================
-- Execucao:
--   psql -U postgres -f database/01_ddl.sql
--
-- O script e idempotente: recria o banco do zero a cada execucao.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Banco de dados
-- ---------------------------------------------------------------------
-- CREATE DATABASE nao pode rodar dentro de um bloco transacional, por isso
-- fica isolado no inicio do arquivo.

DROP DATABASE IF EXISTS clinica_medica;

CREATE DATABASE clinica_medica
    WITH ENCODING 'UTF8'
         TEMPLATE template0;

\connect clinica_medica

-- ---------------------------------------------------------------------
-- 2. Tipos enumerados
-- ---------------------------------------------------------------------
-- Dominios fechados ficam no banco, e nao apenas na validacao da aplicacao.
-- Alem de barrar valor invalido, o ENUM documenta o ciclo de vida da consulta.

CREATE TYPE situacao_consulta AS ENUM (
    'agendada',
    'confirmada',
    'realizada',
    'cancelada',
    'falta'
);

CREATE TYPE forma_pagamento AS ENUM (
    'dinheiro',
    'cartao_credito',
    'cartao_debito',
    'pix',
    'convenio'
);

CREATE TYPE tipo_telefone AS ENUM (
    'celular',
    'residencial',
    'comercial'
);

-- ---------------------------------------------------------------------
-- 3. CIDADES
-- ---------------------------------------------------------------------
-- Existe por causa da 3FN: no modelo nao normalizado, CEP determinava
-- cidade e UF dentro da tabela de pacientes (dependencia transitiva).

CREATE TABLE cidades (
    cidade_id SERIAL      PRIMARY KEY,
    nome      VARCHAR(80) NOT NULL,
    uf        CHAR(2)     NOT NULL,

    CONSTRAINT uq_cidades_nome_uf UNIQUE (nome, uf),
    CONSTRAINT ck_cidades_uf CHECK (uf ~ '^[A-Z]{2}$')
);

COMMENT ON TABLE cidades IS 'Cidade e UF. Removida de pacientes para eliminar a dependencia transitiva CEP -> cidade/UF (3FN).';

-- ---------------------------------------------------------------------
-- 4. CONVENIOS
-- ---------------------------------------------------------------------
-- Existe por causa da 3FN: nome do convenio e registro ANS dependiam do
-- convenio, nao do paciente.

CREATE TABLE convenios (
    convenio_id  SERIAL      PRIMARY KEY,
    nome         VARCHAR(80) NOT NULL,
    registro_ans CHAR(6)     NOT NULL,
    ativo        BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_convenios_nome UNIQUE (nome),
    CONSTRAINT uq_convenios_ans  UNIQUE (registro_ans),
    CONSTRAINT ck_convenios_ans  CHECK (registro_ans ~ '^[0-9]{6}$')
);

COMMENT ON TABLE convenios IS 'Operadoras de plano de saude (RF01). Atributos proprios do convenio saem da tabela de pacientes por 3FN.';

-- ---------------------------------------------------------------------
-- 5. PACIENTES
-- ---------------------------------------------------------------------

CREATE TABLE pacientes (
    paciente_id        BIGSERIAL    PRIMARY KEY,
    nome               VARCHAR(120) NOT NULL,
    cpf                CHAR(11)     NOT NULL,
    data_nascimento    DATE         NOT NULL,
    email              VARCHAR(120),
    convenio_id        INTEGER,
    numero_carteirinha VARCHAR(30),
    -- Endereco em atributos atomicos (1FN): o modelo original guardava
    -- "Rua X, 120 - Centro - Fortaleza/CE" em um unico campo de texto.
    cep                CHAR(8)      NOT NULL,
    logradouro         VARCHAR(120) NOT NULL,
    numero             VARCHAR(10)  NOT NULL,
    complemento        VARCHAR(40),
    bairro             VARCHAR(60)  NOT NULL,
    cidade_id          INTEGER      NOT NULL,
    criado_em          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_pacientes_cpf UNIQUE (cpf),

    -- A carteirinha e unica dentro de cada convenio, nao globalmente.
    CONSTRAINT uq_pacientes_carteirinha UNIQUE (convenio_id, numero_carteirinha),

    CONSTRAINT fk_pacientes_convenio
        FOREIGN KEY (convenio_id) REFERENCES convenios (convenio_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_pacientes_cidade
        FOREIGN KEY (cidade_id) REFERENCES cidades (cidade_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_pacientes_cpf_digitos
        CHECK (cpf ~ '^[0-9]{11}$'),

    CONSTRAINT ck_pacientes_cep_digitos
        CHECK (cep ~ '^[0-9]{8}$'),

    CONSTRAINT ck_pacientes_nascimento_passado
        CHECK (data_nascimento <= CURRENT_DATE),

    CONSTRAINT ck_pacientes_nome_preenchido
        CHECK (length(trim(nome)) >= 3),

    CONSTRAINT ck_pacientes_email_formato
        CHECK (email IS NULL OR email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$'),

    -- Paciente particular nao tem carteirinha; paciente de convenio tem.
    CONSTRAINT ck_pacientes_convenio_coerente
        CHECK (
            (convenio_id IS NULL     AND numero_carteirinha IS NULL)
         OR (convenio_id IS NOT NULL AND numero_carteirinha IS NOT NULL)
        )
);

COMMENT ON TABLE  pacientes IS 'Pessoas atendidas pela clinica (RF01).';
COMMENT ON COLUMN pacientes.cpf IS 'Somente digitos, sem pontuacao. Chave candidata (identificador natural).';
COMMENT ON COLUMN pacientes.convenio_id IS 'NULL para paciente particular.';

-- ---------------------------------------------------------------------
-- 6. TELEFONES_PACIENTE
-- ---------------------------------------------------------------------
-- Existe por causa da 1FN: a planilha original guardava varios telefones
-- em uma unica celula separados por virgula (grupo repetitivo).

CREATE TABLE telefones_paciente (
    telefone_id BIGSERIAL     PRIMARY KEY,
    paciente_id BIGINT        NOT NULL,
    tipo        tipo_telefone NOT NULL DEFAULT 'celular',
    numero      VARCHAR(11)   NOT NULL,

    CONSTRAINT fk_telefones_paciente
        FOREIGN KEY (paciente_id) REFERENCES pacientes (paciente_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT uq_telefones_paciente_numero UNIQUE (paciente_id, numero),

    CONSTRAINT ck_telefones_numero CHECK (numero ~ '^[0-9]{10,11}$')
);

COMMENT ON TABLE telefones_paciente IS 'Telefones do paciente, um por linha (atomicidade exigida pela 1FN).';

-- ---------------------------------------------------------------------
-- 7. ESPECIALIDADES
-- ---------------------------------------------------------------------
-- Existe por causa da 3FN: "Cardiologia" repetido como texto em medicos
-- gerava redundancia e anomalia de atualizacao.

CREATE TABLE especialidades (
    especialidade_id SERIAL      PRIMARY KEY,
    nome             VARCHAR(60) NOT NULL,

    CONSTRAINT uq_especialidades_nome UNIQUE (nome)
);

COMMENT ON TABLE especialidades IS 'Catalogo de especialidades medicas (RF02).';

-- ---------------------------------------------------------------------
-- 8. MEDICOS
-- ---------------------------------------------------------------------

CREATE TABLE medicos (
    medico_id BIGSERIAL    PRIMARY KEY,
    nome      VARCHAR(120) NOT NULL,
    crm       VARCHAR(15)  NOT NULL,
    uf_crm    CHAR(2)      NOT NULL,
    email     VARCHAR(120),
    ativo     BOOLEAN      NOT NULL DEFAULT TRUE,
    criado_em TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- O CRM e unico dentro de cada UF, nao no pais (RF02).
    CONSTRAINT uq_medicos_crm_uf UNIQUE (crm, uf_crm),

    CONSTRAINT ck_medicos_uf_valida  CHECK (uf_crm ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_medicos_crm_digitos CHECK (crm ~ '^[0-9]+$')
);

COMMENT ON TABLE medicos IS 'Profissionais que realizam os atendimentos (RF02).';

-- ---------------------------------------------------------------------
-- 9. MEDICOS_ESPECIALIDADES  (tabela associativa N:N)
-- ---------------------------------------------------------------------
-- No modelo conceitual existe um relacionamento N:N entre Medico e
-- Especialidade. No modelo logico esse relacionamento deixa de existir
-- como linha e passa a ser uma tabela, com PK composta pelas duas FKs.

CREATE TABLE medicos_especialidades (
    medico_id        BIGINT      NOT NULL,
    especialidade_id INTEGER     NOT NULL,
    rqe              VARCHAR(15),
    principal        BOOLEAN     NOT NULL DEFAULT FALSE,

    CONSTRAINT pk_medicos_especialidades
        PRIMARY KEY (medico_id, especialidade_id),

    CONSTRAINT fk_medesp_medico
        FOREIGN KEY (medico_id) REFERENCES medicos (medico_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_medesp_especialidade
        FOREIGN KEY (especialidade_id) REFERENCES especialidades (especialidade_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

COMMENT ON TABLE medicos_especialidades IS 'Resolucao do relacionamento N:N entre medicos e especialidades. PK = juncao das duas FKs.';
COMMENT ON COLUMN medicos_especialidades.rqe IS 'Registro de Qualificacao de Especialista: depende do par (medico, especialidade), por isso pertence a esta tabela.';

-- Cada medico tem no maximo uma especialidade marcada como principal.
CREATE UNIQUE INDEX uq_medesp_principal
    ON medicos_especialidades (medico_id)
    WHERE principal;

-- ---------------------------------------------------------------------
-- 10. CONSULTAS  (entidade central)
-- ---------------------------------------------------------------------

CREATE TABLE consultas (
    consulta_id      BIGSERIAL         PRIMARY KEY,
    paciente_id      BIGINT            NOT NULL,
    medico_id        BIGINT            NOT NULL,
    especialidade_id INTEGER           NOT NULL,
    data_hora        TIMESTAMPTZ       NOT NULL,
    situacao         situacao_consulta NOT NULL DEFAULT 'agendada',
    observacoes      TEXT,
    criado_em        TIMESTAMPTZ       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Paciente com historico nao pode ser apagado (auditoria clinica).
    CONSTRAINT fk_consultas_paciente
        FOREIGN KEY (paciente_id) REFERENCES pacientes (paciente_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_consultas_medico
        FOREIGN KEY (medico_id) REFERENCES medicos (medico_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- A especialidade do atendimento precisa ser uma das especialidades do
    -- medico: a FK composta aponta para a PK da tabela associativa.
    CONSTRAINT fk_consultas_medico_especialidade
        FOREIGN KEY (medico_id, especialidade_id)
        REFERENCES medicos_especialidades (medico_id, especialidade_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_consultas_horizonte
        CHECK (data_hora < CURRENT_TIMESTAMP + INTERVAL '1 year')
);

COMMENT ON TABLE consultas IS 'Agendamento que liga paciente e medico em data e hora (RF03, RF04).';

-- Um medico nao pode ter dois agendamentos ATIVOS no mesmo horario (RF03).
-- O indice e parcial para que um horario cancelado seja reaproveitado.
CREATE UNIQUE INDEX uq_medico_horario
    ON consultas (medico_id, data_hora)
    WHERE situacao IN ('agendada', 'confirmada', 'realizada');

CREATE INDEX ix_consultas_paciente_data ON consultas (paciente_id, data_hora DESC);
CREATE INDEX ix_consultas_medico_data   ON consultas (medico_id, data_hora);

-- ---------------------------------------------------------------------
-- 11. PROCEDIMENTOS
-- ---------------------------------------------------------------------

CREATE TABLE procedimentos (
    procedimento_id SERIAL        PRIMARY KEY,
    codigo_tuss     CHAR(8)       NOT NULL,
    nome            VARCHAR(120)  NOT NULL,
    valor_tabela    NUMERIC(10,2) NOT NULL,

    CONSTRAINT uq_procedimentos_tuss UNIQUE (codigo_tuss),
    CONSTRAINT ck_procedimentos_tuss CHECK (codigo_tuss ~ '^[0-9]{8}$'),
    CONSTRAINT ck_procedimentos_valor CHECK (valor_tabela > 0)
);

COMMENT ON TABLE procedimentos IS 'Catalogo de procedimentos e exames com valor de tabela.';

-- ---------------------------------------------------------------------
-- 12. CONSULTAS_PROCEDIMENTOS  (tabela associativa N:N)
-- ---------------------------------------------------------------------
-- Segunda resolucao de N:N do modelo: uma consulta executa varios
-- procedimentos e um procedimento aparece em varias consultas.

CREATE TABLE consultas_procedimentos (
    consulta_id     BIGINT        NOT NULL,
    procedimento_id INTEGER       NOT NULL,
    quantidade      SMALLINT      NOT NULL DEFAULT 1,
    valor_cobrado   NUMERIC(10,2) NOT NULL,

    CONSTRAINT pk_consultas_procedimentos
        PRIMARY KEY (consulta_id, procedimento_id),

    CONSTRAINT fk_consproc_consulta
        FOREIGN KEY (consulta_id) REFERENCES consultas (consulta_id)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_consproc_procedimento
        FOREIGN KEY (procedimento_id) REFERENCES procedimentos (procedimento_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_consproc_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_consproc_valor      CHECK (valor_cobrado >= 0)
);

COMMENT ON TABLE consultas_procedimentos IS 'Resolucao do N:N entre consultas e procedimentos. PK = juncao das duas FKs.';
COMMENT ON COLUMN consultas_procedimentos.valor_cobrado IS 'Valor efetivamente cobrado. Depende da consulta E do procedimento (pode haver desconto), por isso respeita a 2FN.';

-- ---------------------------------------------------------------------
-- 13. PAGAMENTOS
-- ---------------------------------------------------------------------

CREATE TABLE pagamentos (
    pagamento_id BIGSERIAL       PRIMARY KEY,
    consulta_id  BIGINT          NOT NULL,
    valor        NUMERIC(10,2)   NOT NULL,
    forma        forma_pagamento NOT NULL,
    pago_em      TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Relacionamento 1:1 com consulta.
    CONSTRAINT uq_pagamentos_consulta UNIQUE (consulta_id),

    -- Nao existe pagamento sem consulta vinculada (RNF01).
    CONSTRAINT fk_pagamentos_consulta
        FOREIGN KEY (consulta_id) REFERENCES consultas (consulta_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT ck_pagamentos_valor_positivo CHECK (valor > 0)
);

COMMENT ON TABLE pagamentos IS 'Registro financeiro da consulta realizada (RF05).';

-- ---------------------------------------------------------------------
-- 14. Valor total: calculado, nao armazenado
-- ---------------------------------------------------------------------
-- Guardar valor_total em consultas violaria a 3FN, porque ele e derivado
-- de quantidade x valor_cobrado dos procedimentos. Em vez de uma coluna,
-- o total vive em uma VIEW.

CREATE VIEW vw_faturamento_consulta AS
SELECT c.consulta_id,
       c.paciente_id,
       c.medico_id,
       c.data_hora,
       c.situacao,
       COALESCE(SUM(cp.quantidade * cp.valor_cobrado), 0) AS valor_total,
       p.valor                                            AS valor_pago,
       p.forma                                            AS forma_pagamento
  FROM consultas c
  LEFT JOIN consultas_procedimentos cp ON cp.consulta_id = c.consulta_id
  LEFT JOIN pagamentos p               ON p.consulta_id  = c.consulta_id
 GROUP BY c.consulta_id, c.paciente_id, c.medico_id, c.data_hora, c.situacao,
          p.valor, p.forma;

COMMENT ON VIEW vw_faturamento_consulta IS 'Total da consulta calculado em tempo de consulta, para nao armazenar atributo derivado (3FN).';

-- ---------------------------------------------------------------------
-- 15. Verificacao
-- ---------------------------------------------------------------------

\echo '--- Tabelas criadas ---'
\dt
