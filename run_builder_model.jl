using JuMP, HiGHS, JLD2, XLSX
using Base: deepcopy

include("healthcare_model.jl")
include("model_utils.jl")
include("model_builder.jl")
include("optimization_model.jl")


function example_usage()
    # Carregar dados
    data_path = "dados_PRONTOS_para_modelo_OTM"
    municipio = "Contagem"
    
    println("Carregando dados...")
    data = load_healthcare_data(data_path)
    
    println("Filtrando dados para o município: $municipio")
    mun_data = filter_municipality_data(data, municipio)
    
    #TODOs: Deixar mais facil a definicao dos rais criticos!
    mun_data.constantes.raio_maximo_n1 = 2.0
    #mun_data.constantes.raio_maximo_n2 = 20.0
    #mun_data.constantes.raio_maximo_n3 = 50.0

    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)

    # Criar modelo usando o builder
    println("Criando modelo usando o builder...")

    builder_oficial = CreateHealthcareModelBuilder(deepcopy(parameters), deepcopy(indices), deepcopy(mun_data)) |>
    #without_second_level |>
    #without_third_level |>
    #fixa_alocacoes_primarias_reais |>
    #without_candidates_first_level |>
    without_candidates_second_level |>
    without_candidates_third_level |>

    #without_fix_real_facilities_n1 |>
    #without_fix_real_facilities_n2 |>
    #without_fix_real_facilities_n3 |>

    #without_capacity_constraint_first_level |>
    without_capacity_constraint_second_level |>
    without_capacity_constraint_third_level |>
    build
    println("Resolvendo modelo...")
    optimize!(builder_oficial.model)



    results = extract_results(builder_oficial.model, builder_oficial.indices)
    version_result = "builder_cenario_3"
    println("Salvando resultados e dados...")
    save("resultados_otimizacao_$(version_result).jld2", Dict(
        "results" => results,
        "parameters" => parameters,
        "mun_data" => mun_data,
        "indices" => indices
    ))
    print_parcelas_funcao_objetivo(builder_oficial.model)
    gerar_excel_funcao_objetivo(builder_oficial.model, "resultados_custos_n1.xlsx")
    
    return model, results
end

# Executar o exemplo
if abspath(PROGRAM_FILE) == @__FILE__
    model, results = example_usage()
end 