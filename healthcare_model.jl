using JuMP, HiGHS, DataFrames, XLSX, CSV, Distances

# Estruturas de dados
struct Matriz_Dist
    Matriz_Dist_n1::Matrix{Float64}
    Matriz_Dist_n2::Matrix{Float64}
    Matriz_Dist_n3::Matrix{Float64}
end

mutable struct Domains
    dominio_n1::Dict{Int64, Vector{Int64}}
    dominio_n2::Dict{Int64, Vector{Int64}}
    dominio_n3::Dict{Int64, Vector{Int64}}
    dominio_rest_cap_n1::Vector{Int64}
    dominio_rest_cap_n2::Vector{Int64}
    dominio_rest_cap_n3::Vector{Int64}
    dominio_level_n2::Vector{Int64}
    dominio_level_n3::Vector{Int64}
    dominio_fixa_inst_reais_n1::Vector{Int64}
    dominio_fixa_inst_reais_n2::Vector{Int64}
    dominio_fixa_inst_reais_n3::Vector{Int64}
end


mutable struct HealthcareData
    df_demanda::DataFrame
    df_ins_prim::DataFrame
    df_ins_sec::DataFrame
    df_ins_ter::DataFrame
    df_equipes_primario::DataFrame
    df_equipes_secundario::DataFrame
    df_equipes_terciario::DataFrame
    df_necessidades_primario::DataFrame
    df_necessidades_sec_ter::DataFrame
end

mutable struct ModelConstants
    # Raios máximos
    raio_maximo_n1::Float64
    raio_maximo_n2::Float64
    raio_maximo_n3::Float64
    
    # Custos de abertura
    custo_abertura_n1::Float64
    custo_abertura_n2::Float64
    custo_abertura_n3::Float64
    
    # Custos operacionais
    custo_transporte::Float64
    Cap_n1::Int
    Cap_n2::Int
    Cap_n3::Int
    
    # Custos fixos e variáveis
    S_custo_fixo_n1::Float64
    S_custo_variavel_n1::Vector{Float64}
    S_custo_fixo_n2::Float64
    S_custo_variavel_n2::Vector{Float64}
    S_custo_fixo_n3::Float64
    S_custo_variavel_n3::Vector{Float64}
    
    # Percentuais de fluxo
    percent_n1_n2::Float64
    percent_n2_n3::Float64
    
    # Tipos de pacientes
    S_pacientes::Vector{Int}
    lista_doencas::Vector{String}
    porcentagem_populacao::Vector{Float64}
end

mutable struct MunicipalityData
    nome::String # CD_SETOR => demanda
    S_Valor_Demanda::Vector{Float64}
    coordenadas::Vector{Tuple{Float64, Float64}}
    S_cnes_primario_referencia_real::Vector{Int64}
    unidades_n1::DataFrame
    unidades_n2::DataFrame
    unidades_n3::DataFrame
    equipes_n1::DataFrame
    equipes_n2::DataFrame
    equipes_n3::DataFrame
    constantes::ModelConstants
    IVS::Vector{Float64}
    
end

mutable struct ModelIndices
    S_n1::Vector{Int}
    S_n2::Vector{Int}
    S_n3::Vector{Int}
    S_Pontos_Demanda::Vector{Int}
    S_equipes_n1::Vector{Int}
    S_equipes_n2::Vector{Int}
    S_equipes_n3::Vector{Int}
    S_Locais_Candidatos_n1::Vector{Int}
    S_Locais_Candidatos_n2::Vector{Int}
    S_Locais_Candidatos_n3::Vector{Int}
    S_instalacoes_reais_n1::Vector{Int}
    S_instalacoes_reais_n2::Vector{Int}
    S_instalacoes_reais_n3::Vector{Int}
    S_atribuicoes_reais_por_demanda::Vector{Int}
end

mutable struct ModelParameters
    capacidade_maxima_por_equipe_n1::Vector{Float64}
    S_custo_equipe_n1::Vector{Float64}
    S_eq_por_paciente_n2::Vector{Float64}
    S_custo_equipe_n2::Vector{Float64}
    S_eq_por_paciente_n3::Vector{Float64}
    S_custo_equipe_n3::Vector{Float64}
    S_capacidade_CNES_n1::Matrix{Float64}  # [unidade, tipo_equipe]
    S_capacidade_CNES_n2::Matrix{Float64}  # [unidade, tipo_equipe]
    S_capacidade_CNES_n3::Matrix{Float64}  # [unidade, tipo_equipe]
    S_Matriz_Dist::Matriz_Dist
    S_domains::Domains
    IVS::Vector{Float64}
end

# Funções de leitura de dados
function load_healthcare_data(base_path::String)::HealthcareData
    return HealthcareData(
        DataFrame(XLSX.readtable(joinpath(base_path, "Dados_demanda_demografia_ivs.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_primarias.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_secundarias.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_terciarias.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_primario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_secundario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_terciario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "equipes_Primario_FIM _COMPLETO.xlsb.xlsx"), "necessidades_Primario")),
        DataFrame(XLSX.readtable(joinpath(base_path, "equipes_Primario_FIM _COMPLETO.xlsb.xlsx"), "Necessidades_Sec_ter"))
    )
end

function filter_municipality_data(data::HealthcareData, municipio::String)::MunicipalityData
    muncipio_upper = uppercase(municipio)
    if muncipio_upper == "DIVINÓPOLIS"
        muncipio_upper = "DIVINOPOLIS"
    end
    # Filtrar dados do município
    df_m = data.df_demanda[data.df_demanda.NM_MUN .== municipio, :]
    # Criar dicionários usando eachrow
    S_Valor_Demanda = [row["Total de pessoas"] for row in eachrow(df_m)]
    c_coords = [(row.Latitude, row.Longitude) for row in eachrow(df_m)]
    S_cnes_primario_referencia_real = [row["UBS_ref"] for row in eachrow(df_m)]
    IVS = [row["IVS"] for row in eachrow(df_m)]
    # Quando coletar valores de demanda

    # Definição das constantes do modelo - Dados que precisamos melhorar!.
    raio_maximo_n1 = 3
    raio_maximo_n2 = 30
    raio_maximo_n3 = 50

    custo_abertura_n1 = 500000
    custo_abertura_n2 = 1500000
    custo_abertura_n3 = 5000000

    custo_transporte = 4.5
    Cap_n1 = 10000
    Cap_n2 = 150000
    Cap_n3 = 800000
    S_custo_fixo_n1 = 0.08 * 750000
    S_custo_variavel_n1 = [0.07 * 750000 / 10000, 0.07 * 750000 / 10000]
    
    
    S_custo_fixo_n2 = 0.17 * 2000000
    Custo_abertura_n2 = 6593000
    c_var_n2 = 0.08 * 2000000 / 150000
    S_custo_variavel_n2 = [c_var_n2, c_var_n2]
    
    S_custo_fixo_n3 = 0.19 * 20000000
    c_var_n3 = 0.11 * 20000000 / 800000
    Custo_abertura_n3 = 12000000
    S_custo_variavel_n3 = [c_var_n3, c_var_n3]              

    percent_n1_n2 = 0.4
    percent_n2_n3 = 0.7
    S_pacientes = [1,2]

    lista_doencas = ["Crônico", "Agudo"]
    porcentagem_populacao = [0.54, 0.46]

                    

    return MunicipalityData(
        municipio,
        S_Valor_Demanda,
        c_coords,
        S_cnes_primario_referencia_real,
        data.df_ins_prim[data.df_ins_prim.municipio_nome .== muncipio_upper, :],
        data.df_ins_sec[data.df_ins_sec.municipio_nome .== muncipio_upper, :],
        data.df_ins_ter[data.df_ins_ter.municipio_nome .== muncipio_upper, :],
        data.df_equipes_primario[data.df_equipes_primario.municipio .== muncipio_upper, :],
        data.df_equipes_secundario[data.df_equipes_secundario.municipio .== muncipio_upper, :],
        data.df_equipes_terciario[data.df_equipes_terciario.municipio .== muncipio_upper, :],
        ModelConstants(
            raio_maximo_n1,
            raio_maximo_n2,
            raio_maximo_n3,
            custo_abertura_n1,
            custo_abertura_n2,
            custo_abertura_n3,
            custo_transporte,
            Cap_n1,
            Cap_n2,
            Cap_n3,
            S_custo_fixo_n1,
            S_custo_variavel_n1,
            S_custo_fixo_n2,
            S_custo_variavel_n2,
            S_custo_fixo_n3,
            S_custo_variavel_n3,
            percent_n1_n2,
            percent_n2_n3,
            S_pacientes,
            lista_doencas,
            porcentagem_populacao
        ),
        IVS
    )
end

function calculate_model_parameters(mun_data::MunicipalityData, data::HealthcareData, )::Tuple{ModelIndices, ModelParameters}
    # Aqui você implementaria a lógica de cálculo dos parâmetros do modelo
    # Similar ao que está no seu código original, mas organizado em funções
    # Por exemplo:
    indices = create_model_indices(mun_data)
    parameters = create_model_parameters(mun_data, data, indices)
    return indices, parameters
end

function create_optimization_model_2(indices::ModelIndices, params::ModelParameters)::Model
    model = Model(HiGHS.Optimizer)
    
    # Aqui você implementaria a criação do modelo de otimização
    # Similar ao que está no seu código original, mas organizado
    
    return model
end

function solve_model!(model::Model)
    optimize!(model)
    return solution_summary(model)
end

# Função principal que orquestra todo o processo
function run_healthcare_optimization(municipio::String, data_path::String)
    # Carregar dados
    data = load_healthcare_data(data_path)
    
    # Filtrar dados do município
    mun_data = filter_municipality_data(data, municipio)
    
    # Calcular parâmetros do modelo
    indices, parameters = calculate_model_parameters(mun_data, data)
    
    # Criar e resolver o modelo
    model = create_optimization_model(indices, parameters)

    results = solve_model!(model)
    
    return model, results
end

# Função para criar as constantes do modelo
function create_model_constants()::ModelConstants
    return ModelConstants(
        10.0,   # raio_maximo_n1
        30.0,   # raio_maximo_n2
        50.0,   # raio_maximo_n3
        500000.0,  # custo_abertura_n1
        1500000.0, # custo_abertura_n2
        5000000.0, # custo_abertura_n3
        4.5,    # custo_transporte
        10000,  # Cap_n1
        150000, # Cap_n2
        800000, # Cap_n3
        0.08 * 750000, # S_custo_fixo_n1
        [0.07 * 750000 / 10000, 0.07 * 750000 / 10000], # S_custo_variavel_n1
        0.17 * 2000000, # S_custo_fixo_n2
        [0.08 * 2000000 / 150000, 0.08 * 2000000 / 150000], # S_custo_variavel_n2
        0.19 * 20000000, # S_custo_fixo_n3
        [0.11 * 20000000 / 800000, 0.11 * 20000000 / 800000], # S_custo_variavel_n3
        0.4,    # percent_n1_n2
        0.7,    # percent_n2_n3
        [1, 2], # S_pacientes
        ["Crônico", "Agudo"], # lista_doencas
        [0.54, 0.46] # porcentagem_populacao
    )
end
