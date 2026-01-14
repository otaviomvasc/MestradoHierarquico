# Exemplo de como extrair e exportar resultados da variável pop_atendida
# Este arquivo demonstra como usar as funções criadas para extrair dados da população atendida

using JuMP, HiGHS, JLD2, XLSX, DataFrames

# Incluir os arquivos necessários
include("healthcare_model.jl")
include("model_utils.jl")
include("model_builder.jl")
include("optimization_model.jl")

function exemplo_extrair_resultados_populacao()
    println("=== EXEMPLO DE EXTRAÇÃO DE RESULTADOS DA POPULAÇÃO ATENDIDA ===")
    
    # 1. CARREGAR DADOS E CRIAR MODELO
    println("\n1. Carregando dados...")
    data_path = "dados_PRONTOS_para_modelo_OTM"
    municipio = "Contagem"
    
    data = load_healthcare_data(data_path)
    mun_data = filter_municipality_data(data, municipio)
    
    # Configurar parâmetros
    mun_data.constantes.raio_maximo_n1 = 2.0
    indices, parameters = calculate_model_parameters(mun_data, data)
    parameters.orcamento_maximo = 3000000.0
    parameters.ponderador_Vulnerabilidade = 10.0
    
    # 2. CRIAR E OTIMIZAR MODELO
    println("\n2. Criando e otimizando modelo...")
    model = create_optimization_model_maximal_coverage(indices, parameters, mun_data)
    optimize!(model)
    
    # 3. VERIFICAR SE A OTIMIZAÇÃO FOI BEM-SUCEDIDA
    if termination_status(model) != MOI.OPTIMAL
        println("Erro: Otimização não foi bem-sucedida!")
        return
    end
    
    println("Otimização concluída com sucesso!")
    println("Valor da função objetivo: ", objective_value(model))
    
    # 4. EXTRAIR RESULTADOS DA POPULAÇÃO ATENDIDA
    println("\n3. Extraindo resultados da população atendida...")
    population_results = extract_population_results(model, indices, mun_data)
    
    # 5. EXTRAIR RESULTADOS DO FLUXO DE EQUIPES
    println("\n4. Extraindo resultados do fluxo de equipes...")
    team_flow_results = extract_team_flow_results(model, indices, parameters)
    
    # 6. EXTRAIR RESULTADOS DOS CUSTOS
    println("\n5. Extraindo resultados dos custos...")
    cost_results = extract_cost_results(model)
    
    # 7. EXPORTAR PARA EXCEL
    println("\n6. Exportando para Excel...")
    filename = "resultados_populacao_atendida_$(municipio)_exemplo.xlsx"
    df_results = export_population_results_to_excel(population_results, filename)
    
    # Adicionar dados do fluxo de equipes ao mesmo arquivo Excel
    df_team_flow = add_team_flow_to_excel(team_flow_results, filename)
    
    # Adicionar dados dos custos ao mesmo arquivo Excel
    df_costs = add_cost_results_to_excel(cost_results, filename)
    
    # 8. MOSTRAR RESUMO DOS RESULTADOS
    println("\n7. Resumo dos resultados:")
    println("   - Total de pontos de demanda: ", length(population_results))
    println("   - População total: ", sum([r.populacao_total for r in population_results]))
    println("   - População atendida: ", round(sum([r.populacao_atendida for r in population_results]), digits=0))
    
    # Calcular percentual médio de atendimento
    percentuais = [r.populacao_atendida / r.populacao_total * 100 for r in population_results]
    println("   - Percentual médio de atendimento: ", round(mean(percentuais), digits=2), "%")
    
    # Mostrar alguns exemplos de resultados
    println("\n8. Exemplos de resultados da população:")
    println("   Primeiros 5 pontos de demanda:")
    for i in 1:min(5, length(population_results))
        r = population_results[i]
        println("   Ponto ", i, ": Pop. Total = ", r.populacao_total, ", Pop. Atendida = ", round(r.populacao_atendida, digits=0), ", UBS = ", r.ubs_alocada)
    end
    
    # Mostrar resumo do fluxo de equipes
    println("\n9. Resumo do fluxo de equipes:")
    println("   - Total de combinações UBS-Equipe: ", length(team_flow_results))
    ubs_reais = count([r.tipo_ubs == "Real" for r in team_flow_results])
    ubs_candidatas = count([r.tipo_ubs == "Candidata" for r in team_flow_results])
    println("   - UBSs reais: ", ubs_reais)
    println("   - UBSs candidatas: ", ubs_candidatas)
    println("   - Total de equipes CNES: ", sum([r.quantidade_equipes_cnes for r in team_flow_results]))
    println("   - Total de equipes adicionais (fluxo): ", sum([r.valor_variavel_fluxo for r in team_flow_results]))
    
    # Mostrar resumo dos custos
    println("\n10. Resumo dos custos:")
    println("   - Total de tipos de custo: ", length(cost_results))
    println("   - Custo total: R\$ ", round(sum([r.valor for r in cost_results]), digits=2))
    
    # Mostrar os principais custos
    println("   - Principais componentes:")
    for i in 1:min(3, length(cost_results))
        if cost_results[i].percentual > 0
            println("     • ", cost_results[i].tipo_custo, " (", cost_results[i].nivel, "): R\$ " , round(cost_results[i].valor, digits=2), " (", cost_results[i].percentual, "%)")
        end
    end
    
    # 11. SALVAR RESULTADOS COMPLETOS
    println("\n11. Salvando resultados completos...")
    results = extract_results(model, indices)
    save("resultados_completos_exemplo.jld2", Dict(
        "results" => results,
        "parameters" => parameters,
        "mun_data" => mun_data,
        "indices" => indices,
        "population_results" => population_results,
        "team_flow_results" => team_flow_results,
        "cost_results" => cost_results,
        "df_results" => df_results,
        "df_team_flow" => df_team_flow,
        "df_costs" => df_costs
    ))
    
    println("\n=== PROCESSO CONCLUÍDO COM SUCESSO ===")
    println("Arquivos gerados:")
    println("  - Excel: ", filename, " (com 3 abas: População, Fluxo_Equipes e Custos)")
    println("  - JLD2: resultados_completos_exemplo.jld2")
    
    return model, results, population_results, team_flow_results, cost_results, df_results, df_team_flow, df_costs
end

# Função para carregar e analisar resultados salvos
function carregar_e_analisar_resultados(filename::String)
    println("Carregando resultados de: ", filename)
    
    # Carregar dados
    data = load(filename)
    
    # Extrair componentes
    population_results = data["population_results"]
    df_results = data["df_results"]
    
    # Verificar se existem dados do fluxo de equipes
    has_team_flow = haskey(data, "team_flow_results")
    has_costs = haskey(data, "cost_results")
    
    println("Resultados carregados com sucesso!")
    println("Total de pontos de demanda: ", length(population_results))
    
    if has_team_flow
        team_flow_results = data["team_flow_results"]
        df_team_flow = data["df_team_flow"]
        println("Total de combinações UBS-Equipe: ", length(team_flow_results))
    end
    
    if has_costs
        cost_results = data["cost_results"]
        df_costs = data["df_costs"]
        println("Total de tipos de custo: ", length(cost_results))
    end
    
    # Mostrar estatísticas da população
    if !isnothing(df_results)
        println("\nEstatísticas da População:")
        println("  - População total: ", sum(df_results.Populacao_Total))
        println("  - População atendida: ", round(sum(df_results.Populacao_Atendida), digits=0))
        println("  - Percentual médio: ", round(mean(df_results.Percentual_Atendimento), digits=2), "%")
    end
    
    # Mostrar estatísticas do fluxo de equipes
    if has_team_flow && !isnothing(df_team_flow)
        println("\nEstatísticas do Fluxo de Equipes:")
        println("  - Total de combinações UBS-Equipe: ", nrow(df_team_flow))
        println("  - UBSs reais: ", count(df_team_flow.Tipo_UBS .== "Real"))
        println("  - UBSs candidatas: ", count(df_team_flow.Tipo_UBS .== "Candidata"))
        println("  - Total de equipes CNES: ", sum(df_team_flow.Quantidade_Equipes_CNES))
        println("  - Total de equipes adicionais (fluxo): ", sum(df_team_flow.Valor_Variavel_Fluxo))
        println("  - Total geral de equipes: ", sum(df_team_flow.Total_Equipes))
    end
    
    return data
end

# Executar o exemplo se este arquivo for executado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    model, results, population_results, team_flow_results, df_results, df_team_flow = exemplo_extrair_resultados_populacao()
end
