using JuMP, HiGHS, JLD2, XLSX, DataFrames, PrettyTables, Random
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
    
    # Configurar parâmetros específicos do cenário
    println("Configurando parâmetros do cenário...")
    parameters.orcamento_maximo = 5000000.0
    parameters.ponderador_Vulnerabilidade = 1

    println("Criando modelo de cobertura máxima")
    model = create_optimization_model_maximal_coverage_fluxo_equipes(indices, parameters, mun_data)
    #model = create_optimization_model_maximal_coverage_fluxo_equipes_ESF_e_ESB_ENASF_simplificado(indices, parameters, mun_data)
    println("Otimizando modelo...")

    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "dual_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "time_limit", 300.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)

    optimize!(model)
    
    # Verificar se a otimização foi bem-sucedida
    if termination_status(model) == MOI.OPTIMAL
            # Mostrar total atendido por equipe (somando sobre todos os pontos de demanda e unidades)
    # println("Total atendido por equipe:")
    pop_atendida = value.(model[:pop_atendida])
        for eq in [1,2]
            total_eq = 0.0
           for d in indices.S_Pontos_Demanda, n1 in indices.S_n1
               if n1 in parameters.S_domains.dominio_n1[d]
                   total_eq += value(pop_atendida[d, eq, n1])
               end
           end
          println("Equipe $(eq): ", total_eq)
        end



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
        
       # Exportar para Excel
        filename = "Resultados_COBERTURA_MAXIMA_23_END.xlsx"
        df_results = export_population_results_to_excel(population_results, filename)
        
        # Adicionar dados do fluxo de equipes (novo formato) ao mesmo arquivo Excel
        df_team_flow = add_team_flow_to_excel(team_flow_results, filename)
        
        # Adicionar dados dos custos ao mesmo arquivo Excel
        df_costs  = add_cost_results_to_excel(cost_results, filename)

        # Adicionar equipes criadas ao mesmo arquivo Excel
        df_created = add_created_teams_to_excel(create_teams, filename)
        
        # Adicionar fluxo secundario e terciario()
        df_flow = add_flow_patientes_to_excel(fluxo_secundario_terciario, filename)
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