using JuMP, HiGHS, JLD2, XLSX, DataFrames, PrettyTables, Random, JSON, Gurobi

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
    mun_data.constantes.raio_maximo_n1 = 1.5

    #mun_data.constantes.raio_maximo_n2 = 20.0
    #mun_data.constantes.raio_maximo_n3 = 50.0

    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)
    parameters.raio_critico_eMulti = 3
    # Exporta o campo data.matrix_api para um arquivo JSON externo se ele existir
    
    # Configurar parâmetros específicos do cenário
    println("Configurando parâmetros do cenário...")
    #parameters.orcamento_maximo = 21591350 
    parameters.orcamento_maximo = 15500000
    #parameters.orcamento_maximo = 100000000
    parameters.ponderador_Vulnerabilidade = 1

    println("Criando modelo de cobertura máxima")
    model = create_optimization_model_maximal_coverage_fluxo_equipes(indices, parameters, mun_data)
    #model = create_optimization_model_maximal_coverage_fluxo_equipes_ESF_e_ESB_ENASF_simplificado(indices, parameters, mun_data)
    println("Otimizando modelo...")

    #return model
    # Tempo limite (em segundos)
    set_optimizer_attribute(model, "TimeLimit", 3600.0)
    set_optimizer_attribute(model, "MIPGap", 0.05)
    # Gap absoluto (opcional)
    set_optimizer_attribute(model, "MIPGapAbs", 1e-4)
    # Tolerâncias de factibilidade
    set_optimizer_attribute(model, "FeasibilityTol", 1e-6)  # primal
    set_optimizer_attribute(model, "OptimalityTol", 1e-6)   # dual
    set_optimizer_attribute(model, "OutputFlag", 1)  # 1 = mostrar, 0 = silenciar
    set_optimizer_attribute(model, "Threads", 4) 
    optimize!(model)

    
    # Verificar se a otimização foi bem-sucedida
    if termination_status(model) == MOI.OPTIMAL
        println("Finalizou ...")
        #Se modelo 1 finalizar rodada, gerar modelo que aloca Emulti nas ESF!
        println("Otimização concluída com sucesso!")
        println("Valor da função objetivo: ", objective_value(model))
        pop_atendida_values = value.(model[:pop_atendida])
        total_populacao_atendida = sum(values(pop_atendida_values))
        value(model[:custo_total])
        println("Soma total das populacoes atendidas: ", total_populacao_atendida/2)
        
        # Extrair resultados da população atendida
        println("\nExtraindo resultados da população atendida...")
        population_results = extract_population_results(model, indices, mun_data)
        
        println("\nExtraindo fluxo secundario e terciario...")
        fluxo_secundario_terciario = extract_flow_patients(model, indices, parameters, mun_data)
        # Extrair resultados do fluxo de equipes
        println("\nExtraindo resultados do fluxo de equipes...")
        team_flow_results = extract_team_flow_results(model, indices, parameters, mun_data)
        
        println("\nExtraindo resultados de equipes criadas...")
        create_teams = extract_created_teams_df(model, indices, parameters, mun_data)
        # Extrair resultados dos custos
        println("\nExtraindo resultados dos custos...")
        cost_results = extract_cost_results(model)

        println("\nExtraindo Alocacao ubs enasf")
        alocacao_ubs_emulti = extract_aloc_ubs_enasf(model, indices, parameters, mun_data)
        
       # Exportar para Excel
        filename = "Resultados_COBERTURA_MAXIMA_raio_1.5_KM_GUROBI_ORCAMENTO_PESSIMISTA_milhoes_GAP_1.xlsx"
        df_results = export_population_results_to_excel(population_results, filename)
        
        # Adicionar dados do fluxo de equipes (novo formato) ao mesmo arquivo Excel
        df_team_flow = add_team_flow_to_excel(team_flow_results, filename)
        
        # Adicionar dados dos custos ao mesmo arquivo Excel
        df_costs  = add_cost_results_to_excel(cost_results, filename)

        # Adicionar equipes criadas ao mesmo arquivo Excel
        df_created = add_created_teams_to_excel(create_teams, filename)
        
        # Adicionar fluxo secundario e terciario()
        df_flow = add_flow_patientes_to_excel(fluxo_secundario_terciario, filename)

        df_aloc_ubs_emulti = add_alocacao_ubs_emulti(alocacao_ubs_emulti, filename)
        # Adicionar alocação ESF→Emulti

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