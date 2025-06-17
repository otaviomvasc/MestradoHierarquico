using JuMP, HiGHS, JLD2
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

    builder_oficial = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    #without_second_level |>
    #without_third_level |>
    # fixa_alocacoes_primarias_reais 
    #without_candidates_first_level |>
    without_candidates_second_level |>
    without_candidates_third_level |>

    without_fix_real_facilities_n1 |>
    #without_fix_real_facilities_n2 |>
    #without_fix_real_facilities_n3 |>

    #without_capacity_constraint_first_level |>
    without_capacity_constraint_second_level |>
    without_capacity_constraint_third_level |>
    build
    println("Resolvendo modelo...")
    optimize!(builder_oficial.model)

    builder_alocacoes_n1_fixadas = CreateHealthcareModelBuilder(parameters, indices, mun_data) |>
    #without_second_level |>
    #without_third_level |>
    fixa_alocacoes_primarias_reais |>
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
    optimize!(builder_alocacoes_n1_fixadas.model)
    
    # Extrair e processar resultados
    println("Processando resultados...")
    results = extract_results(builder_alocacoes_n1_fixadas.model, builder_alocacoes_n1_fixadas.indices)
    version_result = "builder_atr_n1_fixado_v1"
    println("Salvando resultados e dados...")
    save("resultados_otimizacao_$(version_result).jld2", Dict(
        "results" => results,
        "parameters" => parameters,
        "mun_data" => mun_data,
        "indices" => indices
    ))
    
    # Imprimir resultados
    println("\nResultados da otimização:")
    println("Status: $(results.status)")
    println("Valor objetivo: $(results.objective_value)")
    println("\nUnidades abertas:")
    println("Nível 1: $(length(results.unidades_abertas_n1)) unidades")
    println("Nível 2: $(length(results.unidades_abertas_n2)) unidades")
    println("Nível 3: $(length(results.unidades_abertas_n3)) unidades")

        #Crio variaveis primeiro!

    
    return model, results
end

# Executar o exemplo
if abspath(PROGRAM_FILE) == @__FILE__
    model, results = example_usage()
end 