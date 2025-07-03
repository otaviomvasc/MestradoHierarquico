# Modelo Hierárquico de Otimização de Atenção à Saúde

Este projeto implementa um modelo de otimização matemática para planejamento hierárquico de redes de atenção à saúde, desenvolvido como parte de um trabalho de mestrado. O modelo utiliza programação linear inteira mista para otimizar a localização e alocação de unidades de saúde em três níveis de atenção.

## 📋 Descrição

O sistema de saúde brasileiro é organizado em uma rede hierárquica com três níveis de atenção:
- **Nível 1 (Primário)**: Unidades Básicas de Saúde (UBS) - atenção básica
- **Nível 2 (Secundário)**: Unidades de Média Complexidade - especialidades médicas
- **Nível 3 (Terciário)**: Hospitais de Alta Complexidade - procedimentos complexos

Este modelo otimiza a localização de unidades de saúde e a alocação de pacientes considerando:
- Custos de abertura e operação
- Capacidades das unidades
- Distâncias geográficas
- Fluxo hierárquico de pacientes entre níveis
- Restrições de raio de cobertura

## 🏗️ Arquitetura do Projeto

### Estrutura de Arquivos

```
MestradoHierarquico/
├── main.jl                          # Script principal de execução
├── run_builder_model.jl             # Execução usando padrão Builder
├── healthcare_model.jl              # Estruturas de dados e funções de carregamento
├── model_builder.jl                 # Padrão Builder para construção flexível do modelo
├── optimization_model.jl            # Implementação do modelo de otimização
├── model_utils.jl                   # Utilitários e funções auxiliares
├── pos_processamento.jl             # Pós-processamento de resultados
├── pos_otm.jl                       # Análise pós-otimização
├── dados_PRONTOS_para_modelo_OTM/   # Dados de entrada
└── README.md                        # Este arquivo
```

### Componentes Principais

#### 1. **Estruturas de Dados** (`healthcare_model.jl`)
- `HealthcareData`: Dados brutos do sistema de saúde
- `MunicipalityData`: Dados filtrados por município
- `ModelConstants`: Parâmetros e constantes do modelo
- `ModelIndices`: Conjuntos e índices para o modelo
- `ModelParameters`: Parâmetros calculados para otimização

#### 2. **Padrão Builder** (`model_builder.jl`)
Sistema flexível para construir diferentes configurações do modelo:
- `without_candidates_*_level`: Remove candidatos de localização
- `without_capacity_constraint_*_level`: Remove restrições de capacidade
- `without_*_level`: Remove níveis inteiros
- `fixa_alocacoes_primarias_reais`: Fixa alocações reais do nível primário

#### 3. **Modelo de Otimização** (`optimization_model.jl`)
Implementa o modelo matemático usando JuMP com solver HiGHS.

## 🚀 Como Usar

### Pré-requisitos

1. **Julia** (versão 1.6 ou superior)
2. **Pacotes Julia necessários**:
   ```julia
   using Pkg
   Pkg.add(["JuMP", "HiGHS", "DataFrames", "XLSX", "CSV", "Distances", "JLD2"])
   ```

### Execução Básica

```julia
# Executar o modelo principal
include("main.jl")
model, results = main("versao_teste")

# Ou usar o builder pattern
include("run_builder_model.jl")
model, results = example_usage()
```

### Configuração de Parâmetros

Os principais parâmetros podem ser ajustados em `healthcare_model.jl`:

```julia
# Raios máximos de cobertura (km)
raio_maximo_n1 = 3.0    # Nível primário
raio_maximo_n2 = 30.0   # Nível secundário  
raio_maximo_n3 = 50.0   # Nível terciário

# Custos de abertura
custo_abertura_n1 = 500000    # R$ 500k
custo_abertura_n2 = 1500000   # R$ 1.5M
custo_abertura_n3 = 5000000   # R$ 5M

# Percentuais de fluxo entre níveis
percent_n1_n2 = 0.4  # 40% dos pacientes do N1 vão para N2
percent_n2_n3 = 0.7  # 70% dos pacientes do N2 vão para N3
```

### Exemplos de Configuração

#### Modelo Completo (3 níveis)
```julia
builder = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    build
```

#### Modelo Apenas Nível Primário
```julia
builder = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    without_second_level |>
    without_third_level |>
    build
```

#### Modelo com Alocações Reais Fixadas
```julia
builder = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    fixa_alocacoes_primarias_reais |>
    without_candidates_second_level |>
    without_candidates_third_level |>
    build
```

## 📊 Dados de Entrada

Os dados devem estar na pasta `dados_PRONTOS_para_modelo_OTM/` com os seguintes arquivos:

- `dados_cidades_full_MG.xlsx`: Dados demográficos e geográficos
- `instalacoes_primarias.xlsx`: Unidades de saúde primárias
- `instalacoes_secundarias.xlsx`: Unidades de saúde secundárias  
- `instalacoes_terciarias.xlsx`: Unidades de saúde terciárias
- `df_equipes_primario.xlsx`: Equipes de saúde primárias
- `df_equipes_secundario.xlsx`: Equipes de saúde secundárias
- `df_equipes_terciario.xlsx`: Equipes de saúde terciárias
- `equipes_Primario_FIM _COMPLETO.xlsb.xlsx`: Necessidades de equipes

## 📈 Resultados

O modelo gera os seguintes resultados:

### Variáveis de Decisão
- **Localização**: Quais unidades abrir em cada nível
- **Alocação**: Como alocar pacientes às unidades
- **Capacidade**: Quantas equipes alocar em cada unidade

### Métricas de Saída
- **Custo total**: Custo de abertura + operação + transporte
- **Cobertura**: Percentual da população atendida
- **Eficiência**: Relação custo-benefício
- **Acessibilidade**: Distância média dos pacientes às unidades

### Arquivos de Saída
- `resultados_otimizacao_[versao].jld2`: Resultados completos em formato Julia
- Logs de execução com estatísticas do modelo

## 🔧 Personalização

### Adicionando Novos Municípios

1. Verificar se os dados do município estão nos arquivos de entrada
2. Ajustar parâmetros específicos do município em `healthcare_model.jl`
3. Executar com o nome do município desejado

### Modificando Restrições

O padrão Builder permite fácil modificação das restrições:

```julia
# Exemplo: modelo sem restrições de capacidade
builder = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    without_capacity_constraint_first_level |>
    without_capacity_constraint_second_level |>
    without_capacity_constraint_third_level |>
    build
```

## 📝 Notas Técnicas

### Solver
- **HiGHS**: Solver de programação linear/mista de código aberto
- **JuMP**: Interface Julia para modelagem matemática

### Performance
- Tempo de resolução varia conforme tamanho do problema
- Municípios maiores podem requerer mais tempo de processamento
- Recomenda-se testar com municípios menores primeiro

### Limitações
- Modelo assume distâncias euclidianas
- Custos baseados em estimativas
- Necessita validação com dados reais

## 🤝 Contribuição

Para contribuir com o projeto:

1. Faça um fork do repositório
2. Crie uma branch para sua feature
3. Implemente suas mudanças
4. Teste com diferentes configurações
5. Submeta um pull request

## 📄 Licença

Este projeto foi desenvolvido como parte de um trabalho acadêmico de mestrado.

## 👨‍🎓 Autor

Desenvolvido como parte de pesquisa de mestrado em Engenharia de Produção/Otimização.

---

**Nota**: Este modelo é uma ferramenta de apoio à decisão e deve ser usado em conjunto com análise especializada e validação de dados.
