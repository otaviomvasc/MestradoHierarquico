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
    println("Criando modelo de cobertura máxima")
    create_optimization_model_maximal_coverage(indices, parameters, mun_data)

    results = extract_results(builder_oficial.model, builder_oficial.indices)
    version_result = "resultados_otimizacao_builder_cenario_4"
    println("Salvando resultados e dados...")
    save("resultados_otimizacao_$(version_result).jld2", Dict(
        "results" => results,
        "parameters" => parameters,
        "mun_data" => mun_data,
        "indices" => indices
    ))
    print_parcelas_funcao_objetivo(builder_oficial.model)
    gerar_excel_funcao_objetivo(builder_oficial.model, "resultados_custos_n4.xlsx")
    
    return model, results
end

# Executar o exemplo
if abspath(PROGRAM_FILE) == @__FILE__
    model, results = example_usage()
end 