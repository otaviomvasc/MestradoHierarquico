using JuMP, HiGHS, DataFrames, XLSX, CSV, Distances,  JSON

# Estruturas de dados
struct Matriz_Dist
    Matriz_Dist_n1::Matrix{Float64}
    Matriz_Dist_n2::Matrix{Float64}
    Matriz_Dist_n3::Matrix{Float64}
    Matriz_Dist_Emulti::Matrix{Float64}
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
    df_equipes_primario_v2::DataFrame
    matrix_distance::Vector{Any}
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
    Setor_Censitario::Vector{String}
    nome::String # CD_SETOR => demanda
    S_Valor_Demanda::Vector{Int}
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
    equipes_ESF_primario_v2::DataFrame
    equipes_ESB_primario_v2::DataFrame
    equipes_ENASF_primario_v2::DataFrame
    
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
    S_Equipes_ESF::Vector{Int}
    S_Equipes_ESB::Vector{Int}
    S_Equipes_ENASF::Vector{Int}
    S_origem_equipes_ESB::Vector{Int}
    S_origem_equipes_ESF::Vector{Int}
    S_origem_equipes_ENASF::Vector{Int}
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
    orcamento_maximo::Float64
    ponderador_Vulnerabilidade::Float64
    S_capacidade_unidades_primarias::Vector{Int64}
end


mutable struct Indices_modelo_alocacao_ESF_Emulti
    UBS_ESF_alocada_real::Vector{Int64}
    ESF_Reais_abertas::Vector{Int64}
    UBS_EMulti_alocada_real::Vector{Int64}
    EMulti_Reais_abertas::Vector{Int64}
    UBS_ESF_alocada_candidata::Vector{Int64}
    ESF_criadas::Vector{Int64}
    UBS_Emulti_criadas::Vector{Int64}
    Emulti_criadas::Vector{Int64}

end

# Funções de leitura de dados
function load_healthcare_data(base_path::String)::HealthcareData
    return HealthcareData(
        DataFrame(XLSX.readtable(joinpath(base_path, "Dados_demanda_demografia_ivs.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_primarias.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_secundarias_Contagem_FIM.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "instalacoes_terciarias.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_primario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_secundario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "df_equipes_terciario.xlsx"), "Sheet1")),
        DataFrame(XLSX.readtable(joinpath(base_path, "equipes_Primario_FIM _COMPLETO.xlsb.xlsx"), "necessidades_Primario")),
        DataFrame(XLSX.readtable(joinpath(base_path, "equipes_Primario_FIM _COMPLETO.xlsb.xlsx"), "Necessidades_Sec_ter")),
        DataFrame(XLSX.readtable(joinpath(base_path, "EQUIPES_NAO_PROCESSADO_MAPA_SUS.xlsx"), "Sheet1")),
    # Leitura do arquivo JSON
    open("C:\\Users\\marce\\OneDrive\\Área de Trabalho\\MestradoHierarquico\\dados_PRONTOS_para_modelo_OTM\\Contagem_matrix_results_full_matrix.json", "r") do io
        matrix_json = JSON.parse(read(io, String))
        # Agora matrix_json contém o conteúdo do arquivo JSON como array de Dicts
    end
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
    S_Setor = [row["CD_SETOR"] for row in eachrow(df_m)]
    S_Valor_Demanda = [row["Total de pessoas"] for row in eachrow(df_m)]
    c_coords = [(row.Latitude, row.Longitude) for row in eachrow(df_m)]
    S_cnes_primario_referencia_real = [row["UBS_ref"] for row in eachrow(df_m)]
    IVS = [row["IVS"] for row in eachrow(df_m)]
    df_eqps_v2 = data.df_equipes_primario_v2[data.df_equipes_primario_v2.NO_MUNICIPIO .== muncipio_upper, :]
    df_eqps_v2 = filter(row -> row.TP_EQUIPE in [70, 73, 76, 71, 72], df_eqps_v2)
    df_eqps_v2.classificacao_final = [
        row.TP_EQUIPE in (70, 73, 76) ? "eSF" :
        row.TP_EQUIPE == 71 ? "eSB" :
        row.TP_EQUIPE == 72 ? "eMulti" :
        missing
        for row in eachrow(df_eqps_v2)
    ]
    # Calcular, para cada CO_CNES, quantos TP_EQUIPE diferentes existem no df_eqps_v2
    # Agrupa por CO_CNES e conta o número total de linhas TP_EQUIPE por CNES (sem deduplicar)
    # Agrupar por CO_CNES e calcular o número de equipes de cada tipo por CNES
    equipes_por_cnes = combine(groupby(df_eqps_v2, :CO_CNES)) do sdf
        n_eSF = count(row -> row.TP_EQUIPE in (70, 73, 76), eachrow(sdf))
        n_eSB = count(row -> row.TP_EQUIPE == 71, eachrow(sdf))
        n_eMulti = count(row -> row.TP_EQUIPE == 72, eachrow(sdf))
        (; n_eSF, n_eSB, n_eMulti)
    end
    # Renomeia as colunas conforme pedido (assumindo que TP_EQUIPE só tem 70, 71, 72 possíveis)

    ##TODO: ATENCAO: Rodar modelo primeiro com ESF e depois voltar para fazer a parte de equipe Bucal!
    eqs_ESF = [70, 73, 76]
    eq_ESB  = [71]
    eq_NASF = [72]


    # Filtra as equipes ESF ativas
    equipes_ESF_filtradas = filter(row -> row.TP_EQUIPE in eqs_ESF && row.ST_ATIVA == 1 && row.ST_EQUIPE_VALIDA == "S", df_eqps_v2)
    equipes_ESB_filtradas = filter(row -> row.TP_EQUIPE in eq_ESB && row.ST_ATIVA == 1  && row.ST_EQUIPE_VALIDA == "S", df_eqps_v2)
    equipes_EMULTI_filtradas = filter(row -> row.TP_EQUIPE in eq_NASF && row.ST_ATIVA == 1  && row.ST_EQUIPE_VALIDA == "S", df_eqps_v2 )
    # Faz o groupby por CO_CNES e conta a quantidade de CO_EQUIPE por CNES
    df_unidades_primario =  data.df_ins_prim[data.df_ins_prim.municipio_nome .== muncipio_upper, :]
    # Realizar o merge do df_unidades_primario com equipes_por_cnes (left join)
    df_unidades_primario_merged = leftjoin(
        df_unidades_primario,
        equipes_por_cnes,
        on = :cnes => :CO_CNES
    )

    # Substituir valores missing por zero nas colunas provenientes de equipes_por_cnes
    for col in [:n_eSF, :n_eSB, :n_eMulti]
        if hasproperty(df_unidades_primario_merged, col)
            replace!(df_unidades_primario_merged[!, col], missing => 0)
        end
    end
    # Quando coletar valores de demanda
    df_unidades_primario_merged.total_equipes = df_unidades_primario_merged.n_eSF .+ df_unidades_primario_merged.n_eSB .+ df_unidades_primario_merged.n_eMulti

    # Mostrar o CNES das unidades que têm total_equipes igual a zero
    # Remover as unidades com total de equipes igual a zero
    df_unidades_primario_merged = filter(row -> row.total_equipes > 0, df_unidades_primario_merged)
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
        S_Setor,
        municipio,
        S_Valor_Demanda,
        c_coords,
        S_cnes_primario_referencia_real,
        df_unidades_primario_merged,
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
        IVS, 
        equipes_ESF_filtradas, 
        equipes_ESB_filtradas,
        equipes_EMULTI_filtradas
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
