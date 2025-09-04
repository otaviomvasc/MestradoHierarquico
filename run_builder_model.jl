using JuMP, HiGHS, JLD2, XLSX, DataFrames
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
    
    println("Filtrando dados para o município: ", municipio)
    mun_data = filter_municipality_data(data, municipio)
    
    #TODOs: Deixar mais facil a definicao dos rais criticos!
    mun_data.constantes.raio_maximo_n1 = 2.0
    #mun_data.constantes.raio_maximo_n2 = 20.0
    #mun_data.constantes.raio_maximo_n3 = 50.0

    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)
    
    # Configurar parâmetros específicos do cenário
    println("Configurando parâmetros do cenário...")
    parameters.orcamento_maximo = 1000000.0
    parameters.ponderador_Vulnerabilidade = 1

    println("Criando modelo de cobertura máxima")
    model = create_optimization_model_maximal_coverage(indices, parameters, mun_data)
    
    println("Otimizando modelo...")
    optimize!(model)
    
    # Verificar se a otimização foi bem-sucedida
    if termination_status(model) == MOI.OPTIMAL
        println("Otimização concluída com sucesso!")
        println("Valor da função objetivo: ", objective_value(model))
        
        # Extrair resultados da população atendida
        println("\nExtraindo resultados da população atendida...")
        population_results = extract_population_results(model, indices, mun_data)
        
        # Extrair resultados do fluxo de equipes
        println("\nExtraindo resultados do fluxo de equipes...")
        team_flow_results = extract_team_flow_results(model, indices, parameters)
        
        # Extrair resultados dos custos
        println("\nExtraindo resultados dos custos...")
        cost_results = extract_cost_results(model)
        
        # Exportar para Excel
        filename = "Resultados_COBERTURA_MAXIMA_6.xlsx"
        df_results = export_population_results_to_excel(population_results, filename)
        
        # Adicionar dados do fluxo de equipes ao mesmo arquivo Excel
        df_team_flow = add_team_flow_to_excel(team_flow_results, filename)
        
        # Adicionar dados dos custos ao mesmo arquivo Excel
        df_costs = add_cost_results_to_excel(cost_results, filename)
        
        # Salvar resultados completos
        #results = extract_results(model, indices)
        version_result = "resultados_otimizacao_builder_cenario_4"
        println("Salvando resultados completos...")
       # save("resultados_otimizacao_" * version_result * ".jld2", Dict(
           #"results" => results,
           # "parameters" => parameters,
           # "mun_data" => mun_data,
           # "indices" => indices,
           # "population_results" => population_results,
           # "team_flow_results" => team_flow_results,
            #"cost_results" => cost_results,
           # "df_team_flow" => df_team_flow,
           # "df_costs" => df_costs
       # ))
        
        return model, results, population_results, team_flow_results, cost_results
    else
        println("Erro na otimização: ", termination_status(model))
        return model, nothing, nothing
    end
end

# Executar o exemplo
if abspath(PROGRAM_FILE) == @__FILE__
    model, results, population_results, team_flow_results, cost_results = example_usage()
end 