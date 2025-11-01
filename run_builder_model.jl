using JuMP, HiGHS, JLD2, XLSX, DataFrames, PrettyTables, Random, JSON
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
    mun_data.constantes.raio_maximo_n1 = 8
    #mun_data.constantes.raio_maximo_n2 = 20.0
    #mun_data.constantes.raio_maximo_n3 = 50.0

    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)
    
    # Exporta o campo data.matrix_api para um arquivo JSON externo se ele existir
    
    # Configurar parâmetros específicos do cenário
    println("Configurando parâmetros do cenário...")
    parameters.orcamento_maximo = 21591350
    parameters.ponderador_Vulnerabilidade = 1

    println("Criando modelo de cobertura máxima")
    model = create_optimization_model_maximal_coverage_fluxo_equipes(indices, parameters, mun_data)
    #model = create_optimization_model_maximal_coverage_fluxo_equipes_ESF_e_ESB_ENASF_simplificado(indices, parameters, mun_data)
    println("Otimizando modelo...")

    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "dual_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "time_limit", 3700.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.001)

    optimize!(model)
    
    # Verificar se a otimização foi bem-sucedida
    if termination_status(model) == MOI.OPTIMAL
        println("Finalizou ...")
        #Se modelo 1 finalizar rodada, gerar modelo que aloca Emulti nas ESF!
        println("Otimização concluída com sucesso!")
        println("Valor da função objetivo: ", objective_value(model))

        
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
    


        println("Criando Modelo Alocacao EsF nas Emultis ...")
        model_emulti, indices_model_emulti = create_model_alocacao_Emulti_ESF(model, indices, parameters, mun_data)
        
        println("Otimizando modelo Emulti...")
        set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-4)
        set_optimizer_attribute(model, "dual_feasibility_tolerance", 1e-4)
        set_optimizer_attribute(model, "time_limit", 300.0)
        set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    
        optimize!(model_emulti)

        aloc_esf_emulti_df = nothing
        if termination_status(model_emulti) == MOI.OPTIMAL
            println("Modelo De alocacao Emulti Finalizado com sucesso")
            println("Extraindo Resultados da Alocacao Emulti")
            aloc_esf_emulti_df = extract_aloc_esf_emulti(model_emulti, indices_model_emulti, indices, mun_data)
        
        end

        
       # Exportar para Excel
        filename = "Resultados_COBERTURA_MAXIMA_raio_8_KM_CUSTOS_FINAL_CAPACITADO_REST_CRIACAO.xlsx"
        df_results = export_population_results_to_excel(population_results, filename)
        
        # Adicionar dados do fluxo de equipes (novo formato) ao mesmo arquivo Excel
        df_team_flow = add_team_flow_to_excel(team_flow_results, filename)
        
        # Adicionar dados dos custos ao mesmo arquivo Excel
        df_costs  = add_cost_results_to_excel(cost_results, filename)

        # Adicionar equipes criadas ao mesmo arquivo Excel
        df_created = add_created_teams_to_excel(create_teams, filename)
        
        # Adicionar fluxo secundario e terciario()
        df_flow = add_flow_patientes_to_excel(fluxo_secundario_terciario, filename)
        # Adicionar alocação ESF→Emulti
        if aloc_esf_emulti_df !== nothing
            df_aloc_esf_emulti = add_aloc_esf_emulti_to_excel(aloc_esf_emulti_df, filename)
        end


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