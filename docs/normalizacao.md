# Normalização até a 3ª Forma Normal

Este documento registra o caminho completo da tabela que a clínica usava antes do
sistema — uma planilha única de atendimentos — até o modelo lógico normalizado que
está no arquivo [`database/01_ddl.sql`](../database/01_ddl.sql).

---

## 1. Ponto de partida: a tabela desnormalizada

A secretaria da clínica controlava os atendimentos em uma planilha com uma linha por
atendimento. Reproduzida como tabela, ela ficaria assim:

**`atendimentos` (0FN — tabela não normalizada)**

| cpf_paciente | nome_paciente | telefones | endereco_completo | convenio | registro_ans | carteirinha | crm_medico | nome_medico | especialidades_medico | data_hora | procedimentos | valor_total | forma_pagamento |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 529.982.247-25 | Mariana Alves Rocha | (85) 98877-6655, (85) 3233-4455 | Av. Santos Dumont, 1800, Sala 4 - Aldeota - Fortaleza/CE - 60150-160 | Unimed Ceará | 301001 | 0012345678 | 14523-CE | Dra. Helena Castro | Cardiologia, Clínica Médica | 10/11/2026 09:00 | Consulta (250,00), ECG (90,00) | 340,00 | Convênio |
| 111.444.777-35 | João Pedro Lima | (85) 99111-2233 | Rua Padre Guerra, 420 - Parquelândia - Fortaleza/CE - 60510-000 | Hapvida Saúde | 368253 | 0098765432 | 20871-CE | Dr. Rafael Monteiro | Ortopedia | 12/11/2026 14:30 | Consulta (250,00), RX joelho 2x (110,00) | 470,00 | PIX |
| 529.982.247-25 | Mariana A. Rocha | (85) 98877-6655 | Av. Santos Dumont, 1800 - Aldeota - Fortaleza/CE - 60150-160 | Unimed CE | 301001 | 0012345678 | 14523-CE | Dra. Helena Castro | Cardiologia, Clínica Médica | 02/12/2026 10:00 | Consulta (250,00) | 250,00 | Convênio |

### 1.1 Anomalias que essa tabela produz

| Anomalia | O que acontece na prática |
| --- | --- |
| **Inserção** | Não é possível cadastrar um convênio novo, um médico recém-contratado ou um procedimento da tabela TUSS antes que exista um atendimento. O dado só entra no sistema de carona em uma consulta. |
| **Atualização** | A Unimed muda de razão social. O nome precisa ser corrigido em todas as linhas de todos os pacientes daquele convênio. Se uma linha escapar, o banco passa a afirmar duas coisas diferentes ao mesmo tempo — exatamente o que já aconteceu na linha 3, onde o mesmo convênio aparece como "Unimed CE" e o mesmo paciente como "Mariana A. Rocha". |
| **Exclusão** | Apagar o único atendimento de um paciente apaga junto o cadastro dele, os telefones e o endereço. Em uma clínica, isso é perda de prontuário. |
| **Redundância** | Nome, endereço e telefone do paciente são regravados a cada atendimento. Em três anos de histórico, o mesmo endereço aparece dezenas de vezes. |

---

## 2. Primeira Forma Normal (1FN) — atributos atômicos

> **Regra:** todo atributo deve conter um único valor. Não pode haver grupos
> repetitivos, listas dentro de uma célula nem campos compostos.

Violações encontradas:

| Atributo | Problema | Solução |
| --- | --- | --- |
| `telefones` | Dois números na mesma célula, separados por vírgula. | Tabela `telefones_paciente`, uma linha por telefone. |
| `endereco_completo` | Logradouro, número, complemento, bairro, cidade, UF e CEP em um único texto. | Colunas separadas: `logradouro`, `numero`, `complemento`, `bairro`, `cep` (+ `cidade_id`). |
| `especialidades_medico` | Lista de especialidades em uma célula. | Relacionamento N:N entre médico e especialidade. |
| `procedimentos` | Lista de procedimentos e valores em uma célula. | Relacionamento N:N entre consulta e procedimento. |
| `cpf`, `crm` | Pontuação misturada ao dado. | Armazenados apenas com dígitos; a formatação é responsabilidade da interface. |

Resultado da 1FN: uma tabela `atendimentos` com uma linha por **procedimento de cada
atendimento**, o que torna a chave primária composta:

```
PK (cpf_paciente, data_hora, codigo_tuss)
```

A tabela está atômica, mas a repetição aumentou — e é justamente essa chave composta
que expõe os problemas tratados na 2FN.

---

## 3. Segunda Forma Normal (2FN) — sem dependências parciais

> **Regra:** estando em 1FN, todo atributo não-chave deve depender da chave primária
> **inteira**, e não de apenas parte dela.

Dependências funcionais observadas na tabela em 1FN:

```
cpf_paciente                                  -> nome_paciente, data_nascimento, endereco, convenio, carteirinha
codigo_tuss                                   -> nome_procedimento, valor_tabela
crm_medico                                    -> nome_medico
(cpf_paciente, data_hora)                     -> crm_medico, situacao, observacoes, forma_pagamento
(cpf_paciente, data_hora, codigo_tuss)        -> quantidade, valor_cobrado
```

As três primeiras linhas são **dependências parciais**: os atributos dependem de um
pedaço da chave, não dela inteira. O efeito prático é a redundância em massa — o nome
do paciente é repetido em cada procedimento de cada consulta dele.

Decomposição aplicada:

| Tabela gerada | Chave primária | Atributos que migraram |
| --- | --- | --- |
| `pacientes` | `paciente_id` (`cpf` como chave candidata) | nome, data de nascimento, e-mail, endereço, convênio, carteirinha |
| `procedimentos` | `procedimento_id` (`codigo_tuss` como chave candidata) | nome, valor de tabela |
| `medicos` | `medico_id` (`crm + uf_crm` como chave candidata) | nome, e-mail, ativo |
| `consultas` | `consulta_id` | paciente, médico, especialidade, data/hora, situação, observações |
| `consultas_procedimentos` | `(consulta_id, procedimento_id)` | quantidade, valor cobrado |

Depois dessa etapa, só sobraram na tabela associativa os atributos que realmente
dependem das duas chaves ao mesmo tempo: `quantidade` e `valor_cobrado` (o valor pode
ser negociado para aquela consulta específica e por isso não é o `valor_tabela` do
procedimento).

---

## 4. Terceira Forma Normal (3FN) — sem dependências transitivas

> **Regra:** estando em 2FN, nenhum atributo não-chave pode depender de outro atributo
> não-chave. Todo atributo deve depender da chave, da chave inteira e de nada além da
> chave.

Dependências transitivas que ainda restavam:

| Dependência encontrada | Leitura | Correção |
| --- | --- | --- |
| `paciente_id -> cep -> cidade, uf` | Cidade e UF não dependem do paciente; dependem do CEP. | Tabela `cidades`, referenciada por `cidade_id`. |
| `paciente_id -> convenio -> registro_ans, nome_convenio` | Registro ANS é atributo do convênio, não do paciente. | Tabela `convenios`, referenciada por `convenio_id`. |
| `medico_id -> especialidade -> (texto repetido)` | "Cardiologia" escrito em texto livre em cada médico. | Tabela `especialidades` + associativa `medicos_especialidades`. |
| `consulta_id -> valor_total` | `valor_total` é derivado de `SUM(quantidade * valor_cobrado)`. | **Não armazenado.** Calculado na view `vw_faturamento_consulta`. |

O caso do `valor_total` merece registro: ele não é apenas uma dependência transitiva,
é um **atributo derivado**. Guardá-lo em `consultas` criaria uma segunda fonte da
verdade — bastaria alguém corrigir o valor de um procedimento para o total gravado
ficar mentindo. Mantê-lo em uma view garante que o número exibido sempre reflita as
linhas que o compõem. Se um dia o volume de dados tornar o cálculo caro, a
desnormalização pode ser reintroduzida de forma consciente (coluna materializada +
*trigger* de manutenção), mas isso passa a ser uma decisão de desempenho documentada,
e não um descuido de modelagem.

---

## 5. Resultado final

| # | Tabela | PK | FKs |
| --- | --- | --- | --- |
| 1 | `cidades` | `cidade_id` | — |
| 2 | `convenios` | `convenio_id` | — |
| 3 | `pacientes` | `paciente_id` | `convenio_id`, `cidade_id` |
| 4 | `telefones_paciente` | `telefone_id` | `paciente_id` |
| 5 | `especialidades` | `especialidade_id` | — |
| 6 | `medicos` | `medico_id` | — |
| 7 | `medicos_especialidades` | `(medico_id, especialidade_id)` | `medico_id`, `especialidade_id` |
| 8 | `consultas` | `consulta_id` | `paciente_id`, `(medico_id, especialidade_id)` |
| 9 | `procedimentos` | `procedimento_id` | — |
| 10 | `consultas_procedimentos` | `(consulta_id, procedimento_id)` | `consulta_id`, `procedimento_id` |
| 11 | `pagamentos` | `pagamento_id` | `consulta_id` (único — relacionamento 1:1) |

As mesmas três anomalias do início, agora:

- **Inserção:** um convênio, um médico ou um procedimento novo é cadastrado na sua
  própria tabela, sem depender de atendimento nenhum.
- **Atualização:** o nome da Unimed existe em exatamente uma linha de `convenios`. Uma
  única alteração corrige o sistema inteiro, e não há como ficar inconsistente.
- **Exclusão:** apagar uma consulta não toca no cadastro do paciente. E apagar um
  paciente com histórico é bloqueado pelo `ON DELETE RESTRICT` da FK.

---

## 6. O que fica fora dessa normalização

O **registro clínico** do projeto é persistido no MongoDB e não passa por formas
normais. A decisão foi tomada na Semana 14 e continua válida: o conteúdo do prontuário
varia por especialidade e é sempre lido por inteiro, então ele é um documento
autocontido, não um conjunto de tabelas. A ligação com a parte relacional é feita pela
referência `consulta_id`, que o MongoDB guarda mas não valida — essa consistência é
responsabilidade da aplicação, e é o custo assumido da arquitetura híbrida.
