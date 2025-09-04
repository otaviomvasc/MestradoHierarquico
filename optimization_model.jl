# Estrutura para armazenar resultados
struct OptimizationResults
    objective_value::Float64
    status::String
    unidades_abertas_n1::Vector{Int}
    unidades_abertas_n2::Vector{Int}
    unidades_abertas_n3::Vector{Int}
    atribuicoes::Dict{Int, Int}  # ponto_demanda => unidade_n1
    fluxos::Dict{Tuple{Int,Int,Int,Int}, Float64}  # (origem,destino,tipo) => fluxo
    equipes::Dict{Tuple{Int,Int,Int}, Float64}  # (nivel,unidade,tipo_equipe) => quantidade
end

# Estrutura para armazenar resultados detalhados da população atendida
struct PopulationResults
    setor::String
    ponto_demanda::Int
    populacao_total::Int
    populacao_atendida::Float64
    ubs_alocada::Int
    coord_demanda_lat::Float64
    coord_demanda_lon::Float64
    coord_ubs_lat::Float64
    coord_ubs_lon::Float64
    ivs::Float64
end

# Estrutura para armazenar resultados do fluxo de equipes
struct TeamFlowResults
    ubs::Int
    quantidade_equipes_cnes::Float64
    valor_variavel_fluxo::Float64
    tipo_ubs::String  # "Real" ou "Candidata"
end

# Estrutura para armazenar resultados dos custos
struct CostResults
    tipo_custo::String
    nivel::String
    valor::Float64
    percentual::Float64
    descricao::String
end

function extract_results(model::Model, indices::ModelIndices)::OptimizationResults
    # Extrair valores das variáveis

    flag_has_2_nivel = length(indices.S_n2) > 0 ? true : false
    flag_has_3_nivel = length(indices.S_n3) > 0 ? true : false

    abr_n1 = value.(model[:Abr_n1])
    aloc = value.(model[:Aloc_])
    x_n1 = value.(model[:X_n1])
    eq_n1 = value.(model[:eq_n1])
    unidades_n1 = [i for i in indices.S_n1 if abr_n1[i] > 0.5]
    unidades_n2 = []
    unidades_n3 = []
    equipes = Dict{Tuple{Int,Int,Int}, Float64}()

    if flag_has_2_nivel
        abr_n2 = value.(model[:Abr_n2])
        x_n2 = value.(model[:X_n2])
        eq_n2 = value.(model[:eq_n2])
        unidades_n2 = [i for i in indices.S_n2 if abr_n2[i] > 0.5]
    end

    if flag_has_3_nivel
        abr_n3 = value.(model[:Abr_n3])
        x_n3 = value.(model[:X_n3])
        eq_n3 = value.(model[:eq_n3])
        unidades_n3 = [i for i in indices.S_n3 if abr_n3[i] > 0.5]
    end

    # Criar dicionário de equipes
    # Processar resultados
    
    atribuicoes = Dict{Int,Int}()
    for i in indices.S_Pontos_Demanda
        for j in indices.S_n1
            if haskey(aloc, (i,j)) && aloc[i,j] > 0.5
                atribuicoes[i] = j
                break
            end
        end
    end
    
    # Criar dicionário de fluxos
    fluxos = Dict{Tuple{Int,Int,Int, Int}, Float64}()
    for i in indices.S_Pontos_Demanda, j in indices.S_n1
        if haskey(x_n1, (i,j, 1)) && x_n1[i,j,1] > 0
            for p in 1:2
                fluxos[(1,i,j,p)] = x_n1[i,j,p]
            end
        end
    end

    if flag_has_2_nivel
        for i in indices.S_n1, j in indices.S_n2
            if haskey(x_n2, (i,j, 1)) && x_n2[i,j,1] > 0
                for p in 1:2
                    fluxos[(2,i,j,p)] = x_n2[i,j,p]
                end
            end
        end
    end

    if flag_has_3_nivel
        for i in indices.S_n2, j in indices.S_n3
            if haskey(x_n3, (i,j, 1)) && x_n3[i,j,1] > 0
                for p in 1:2
                    fluxos[(3,i,j,p)] = x_n3[i,j,p]
                end
            end
        end
    end
    
    
    for j in indices.S_n1, k in indices.S_equipes_n1
        #if haskey(eq_n1, (k,j)) && eq_n1[k,j] > 0
            equipes[(1,j,k)] = eq_n1[k,j]
        #end
    end


    if flag_has_2_nivel
        for j in indices.S_n2, k in indices.S_equipes_n2
            #if haskey(eq_n2, (k,j)) && eq_n2[k,j] > 0
                equipes[(2,j,k)] = eq_n2[k,j]
            #end
        end
    end

    if flag_has_3_nivel
        for j in indices.S_n3, k in indices.S_equipes_n3
            #if haskey(eq_n3, (k,j)) && eq_n3[k,j] > 0
                equipes[(3,j,k)] = eq_n3[k,j]
            #end
        end
    end
    
    return OptimizationResults(
        objective_value(model),
        string(termination_status(model)),
        unidades_n1,
        unidades_n2,
        unidades_n3,
        atribuicoes,
        fluxos,
        equipes
    )
end

"""
Extrai os resultados da variável pop_atendida e retorna uma lista de PopulationResults
"""
function extract_population_results(model::Model, indices::ModelIndices, mun_data::MunicipalityData)::Vector{PopulationResults}
    println("Extraindo resultados da população atendida...")
    
    # Verificar se a variável pop_atendida existe no modelo
    if !haskey(model.obj_dict, :pop_atendida)
        error("Variável pop_atendida não encontrada no modelo!")
    end
    
    # Extrair valores da variável pop_atendida
    pop_atendida_values = value.(model[:pop_atendida])
    
    # Extrair valores da variável de alocação
    aloc_values = value.(model[:Aloc_])
    
    results = PopulationResults[]
    
    # Para cada ponto de demanda
    for d in indices.S_Pontos_Demanda
        # População total do ponto de demanda
        setor = mun_data.Setor_Censitario[d]
        populacao_total = mun_data.S_Valor_Demanda[d]
        
        # Coordenadas do ponto de demanda
        coord_demanda = mun_data.coordenadas[d]
        coord_demanda_lat = coord_demanda[1]
        coord_demanda_lon = coord_demanda[2]
        ivs = parameters.IVS[d]

        
        # Encontrar UBS alocada para este ponto de demanda
        ubs_alocada = -1
        for n1 in indices.S_n1
            if haskey(aloc_values, (d, n1)) && aloc_values[d, n1] > 0.5
                ubs_alocada = n1
                break
            end
        end
        
        # Calcular população total atendida (soma de todas as equipes)
        populacao_atendida_total = 0.0
        for eq in indices.S_equipes_n1
            for n1 in indices.S_n1
                if haskey(pop_atendida_values, (d, eq, n1)) && pop_atendida_values[d, eq, n1] > 0
                    populacao_atendida_total += pop_atendida_values[d, eq, n1]
                end
            end
        end
        
        # Coordenadas da UBS alocada
        coord_ubs_lat = 0.0
        coord_ubs_lon = 0.0
        
        if ubs_alocada > 0
            if ubs_alocada <= length(mun_data.unidades_n1.cnes)
                # É uma UBS real
                ubs_row = mun_data.unidades_n1[ubs_alocada, :]
                coord_ubs_lat = ubs_row.latitude
                coord_ubs_lon = ubs_row.longitude
            else
                # É uma UBS candidata (localizada no ponto de demanda)
                candidata_idx = ubs_alocada - length(mun_data.unidades_n1.cnes)
                if candidata_idx <= length(mun_data.coordenadas)
                    coord_ubs_lat = mun_data.coordenadas[candidata_idx][1]
                    coord_ubs_lon = mun_data.coordenadas[candidata_idx][2]
                end
            end
        end
        
        # Criar resultado para este ponto de demanda
        result = PopulationResults(
            setor,
            d,                          # ponto_demanda
            populacao_total,            # populacao_total
            populacao_atendida_total,   # populacao_atendida
            ubs_alocada,                # ubs_alocada
            coord_demanda_lat,          # coord_demanda_lat
            coord_demanda_lon,          # coord_demanda_lon
            coord_ubs_lat,              # coord_ubs_lat
            coord_ubs_lon,
            ivs               # coord_ubs_lon
        )
        
        push!(results, result)
    end
    
    println("Extraídos resultados para ", length(results), " pontos de demanda")
    return results
end

"""
Gera uma tabela Excel com os resultados da população atendida
"""
function export_population_results_to_excel(population_results::Vector{PopulationResults}, 
                                          filename::String="resultados_populacao_atendida.xlsx")
    println("Gerando tabela Excel: ", filename)
    
    # Criar DataFrame com os resultados
    df = DataFrame(
        "Setor" => [r.setor for r in population_results], 
        "Ponto_Demanda" => [r.ponto_demanda for r in population_results],
        "Populacao_Total" => [r.populacao_total for r in population_results],
        "Populacao_Atendida" => [r.populacao_atendida for r in population_results],
        "UBS_Alocada" => [r.ubs_alocada for r in population_results],
        "Lat_Demanda" => [r.coord_demanda_lat for r in population_results],
        "Lon_Demanda" => [r.coord_demanda_lon for r in population_results],
        "Lat_UBS" => [r.coord_ubs_lat for r in population_results],
        "Lon_UBS" => [r.coord_ubs_lon for r in population_results], 
        "IVS" => [r.ivs for r in population_results]
    )
    
    # Adicionar coluna de percentual de atendimento
    #df[!, "Percentual_Atendimento"] = [round(r.populacao_atendida / r.populacao_total * 100, digits=2) for r in population_results]
    
    # Salvar no Excel
    XLSX.writetable(filename, df)
    
    println("Tabela salva com sucesso!")
    println("Resumo dos resultados:")
    println("  - Total de pontos de demanda: ", nrow(df))
    println("  - População total: ", sum(df.Populacao_Total))
    println("  - População atendida: ", round(sum(df.Populacao_Atendida), digits=0))
    #println("  - Percentual médio de atendimento: ", round(mean(df.Percentual_Atendimento), digits=2), "%")
    
    return df
end

"""
Extrai os resultados dos custos do modelo e retorna uma lista de CostResults
"""
function extract_cost_results(model::Model)::Vector{CostResults}
    println("Extraindo resultados dos custos...")
    
    results = CostResults[]
    
    # Calcular custo total para calcular percentuais
    custo_total = 0.0
    
    # Custos do nível 1 (Primário)
    custo_fixo_novos_n1 = value(model[:custo_fixo_novos_n1])
    custo_times_novos_n1 = value(model[:custo_times_novos_n1])
    custo_variavel_n1 = value(model[:custo_variavel_n1])
    
    # Custos do nível 2 (Secundário) - se existirem
    custo_logistico_n2 = 0.0
    custo_fixo_existente_n2 = 0.0
    custo_times_novos_n2 = 0.0
    custo_variavel_n2 = 0.0
    
    if haskey(model.obj_dict, :custo_logistico_n2)
        custo_logistico_n2 = value(model[:custo_logistico_n2])
    end
    if haskey(model.obj_dict, :custo_fixo_existente_n2)
        custo_fixo_existente_n2 = value(model[:custo_fixo_existente_n2])
    end
    if haskey(model.obj_dict, :custo_times_novos_n2)
        custo_times_novos_n2 = value(model[:custo_times_novos_n2])
    end
    if haskey(model.obj_dict, :custo_variavel_n2)
        custo_variavel_n2 = value(model[:custo_variavel_n2])
    end
    
    # Custos do nível 3 (Terciário) - se existirem
    custo_logistico_n3 = 0.0
    custo_fixo_existente_n3 = 0.0
    custo_times_novos_n3 = 0.0
    custo_variavel_n3 = 0.0
    
    if haskey(model.obj_dict, :custo_logistico_n3)
        custo_logistico_n3 = value(model[:custo_logistico_n3])
    end
    if haskey(model.obj_dict, :custo_fixo_existente_n3)
        custo_fixo_existente_n3 = value(model[:custo_fixo_existente_n3])
    end
    if haskey(model.obj_dict, :custo_times_novos_n3)
        custo_times_novos_n3 = value(model[:custo_times_novos_n3])
    end
    if haskey(model.obj_dict, :custo_variavel_n3)
        custo_variavel_n3 = value(model[:custo_variavel_n3])
    end
    
    # Custos agregados
    custo_logistico_total = custo_logistico_n2 + custo_logistico_n3
    custo_fixo_novo_total = custo_fixo_novos_n1
    custo_fixo_existente_total = custo_fixo_existente_n2 + custo_fixo_existente_n3
    custo_times_novos_total = custo_times_novos_n1 + custo_times_novos_n2 + custo_times_novos_n3
    custo_variavel_total = custo_variavel_n1 + custo_variavel_n2 + custo_variavel_n3
    
    # Calcular custo total
    custo_total = custo_logistico_total + custo_fixo_novo_total + custo_fixo_existente_total + custo_times_novos_total + custo_variavel_total
    
    # Adicionar custos por nível
    push!(results, CostResults("Fixo Novos", "Primário", custo_fixo_novos_n1, 
                              round(100 * custo_fixo_novos_n1 / custo_total, digits=2),
                              "Custo de abertura de novas unidades"))
    
    push!(results, CostResults("Equipes Novas", "Primário", custo_times_novos_n1,
                              round(100 * custo_times_novos_n1 / custo_total, digits=2),
                              "Custo das novas equipes"))
    
    push!(results, CostResults("Variável", "Primário", custo_variavel_n1,
                              round(100 * custo_variavel_n1 / custo_total, digits=2),
                              "Custo variável por paciente"))
    
    # Nível 2 (se existir)
    if custo_logistico_n2 > 0 || custo_fixo_existente_n2 > 0 || custo_times_novos_n2 > 0 || custo_variavel_n2 > 0
        push!(results, CostResults("Logístico", "Secundário", custo_logistico_n2,
                                  round(100 * custo_logistico_n2 / custo_total, digits=2),
                                  "Custo de transporte nível secundário"))
        
        push!(results, CostResults("Fixo Existente", "Secundário", custo_fixo_existente_n2,
                                  round(100 * custo_fixo_existente_n2 / custo_total, digits=2),
                                  "Custo fixo das unidades existentes"))
        
        push!(results, CostResults("Equipes Novas", "Secundário", custo_times_novos_n2,
                                  round(100 * custo_times_novos_n2 / custo_total, digits=2),
                                  "Custo das novas equipes"))
        
        push!(results, CostResults("Variável", "Secundário", custo_variavel_n2,
                                  round(100 * custo_variavel_n2 / custo_total, digits=2),
                                  "Custo variável por paciente"))
    end
    
    # Nível 3 (se existir)
    if custo_logistico_n3 > 0 || custo_fixo_existente_n3 > 0 || custo_times_novos_n3 > 0 || custo_variavel_n3 > 0
        push!(results, CostResults("Logístico", "Terciário", custo_logistico_n3,
                                  round(100 * custo_logistico_n3 / custo_total, digits=2),
                                  "Custo de transporte nível terciário"))
        
        push!(results, CostResults("Fixo Existente", "Terciário", custo_fixo_existente_n3,
                                  round(100 * custo_fixo_existente_n3 / custo_total, digits=2),
                                  "Custo fixo das unidades existentes"))
        
        push!(results, CostResults("Equipes Novas", "Terciário", custo_times_novos_n3,
                                  round(100 * custo_times_novos_n3 / custo_total, digits=2),
                                  "Custo das novas equipes"))
        
        push!(results, CostResults("Variável", "Terciário", custo_variavel_n3,
                                  round(100 * custo_variavel_n3 / custo_total, digits=2),
                                  "Custo variável por paciente"))
    end
    
    # Custos agregados
    push!(results, CostResults("Logístico Total", "Agregado", custo_logistico_total,
                              round(100 * custo_logistico_total / custo_total, digits=2),
                              "Custo total de transporte"))
    
    push!(results, CostResults("Fixo Novo Total", "Agregado", custo_fixo_novo_total,
                              round(100 * custo_fixo_novo_total / custo_total, digits=2),
                              "Custo total de abertura de novas unidades"))
    
    push!(results, CostResults("Fixo Existente Total", "Agregado", custo_fixo_existente_total,
                              round(100 * custo_fixo_existente_total / custo_total, digits=2),
                              "Custo fixo total das unidades existentes"))
    
    push!(results, CostResults("Equipes Novas Total", "Agregado", custo_times_novos_total,
                              round(100 * custo_times_novos_total / custo_total, digits=2),
                              "Custo total das novas equipes"))
    
    push!(results, CostResults("Variável Total", "Agregado", custo_variavel_total,
                              round(100 * custo_variavel_total / custo_total, digits=2),
                              "Custo variável total por paciente"))
    
    # Custo total
    push!(results, CostResults("CUSTO TOTAL", "Total", custo_total, 100.0, "Custo total do sistema"))
    
    println("Extraídos resultados para ", length(results), " tipos de custo")
    return results
end

"""
Extrai os resultados da variável fluxo_eq_n1 (eq_n1) e retorna uma lista de TeamFlowResults
"""
function extract_team_flow_results(model::Model, indices::ModelIndices, parameters::ModelParameters)::Vector{TeamFlowResults}
    println("Extraindo resultados do fluxo de equipes...")
    
    # Verificar se a variável eq_n1 existe no modelo
    if !haskey(model.obj_dict, :eq_n1)
        error("Variável eq_n1 não encontrada no modelo!")
    end
    
    # Extrair valores da variável fluxo_eq_n1 (eq_n1)
    fluxo_eq_values = value.(model[:eq_n1])
    
    results = TeamFlowResults[]
    
    # Para cada UBS e equipe
    for n1 in indices.S_n1
        for eq in indices.S_equipes_n1
            # Obter valor da variável de fluxo
            valor_fluxo = fluxo_eq_values[eq, n1]
            
            # Obter quantidade de equipes CNES (capacidade existente)
            quantidade_cnes = 0.0
            if n1 <= size(parameters.S_capacidade_CNES_n1, 1) && eq <= size(parameters.S_capacidade_CNES_n1, 2)
                quantidade_cnes = parameters.S_capacidade_CNES_n1[n1, eq]
            end
            
            # Determinar tipo da UBS
            tipo_ubs = n1 <= length(indices.S_instalacoes_reais_n1) ? "Real" : "Candidata"
            
            # Criar resultado
            result = TeamFlowResults(
                n1,                    # ubs
                quantidade_cnes,       # quantidade_equipes_cnes
                valor_fluxo,           # valor_variavel_fluxo
                tipo_ubs               # tipo_ubs
            )
            
            push!(results, result)
        end
    end
    
    println("Extraídos resultados para ", length(results), " combinações UBS-Equipe")
    return results
end

"""
Gera uma tabela Excel com os resultados do fluxo de equipes
"""
function export_team_flow_results_to_excel(team_flow_results::Vector{TeamFlowResults}, 
                                         filename::String="resultados_fluxo_equipes.xlsx")
    println("Gerando tabela Excel do fluxo de equipes: ", filename)
    
    # Criar DataFrame com os resultados
    df = DataFrame(
        "UBS" => [r.ubs for r in team_flow_results],
        "Quantidade_Equipes_CNES" => [r.quantidade_equipes_cnes for r in team_flow_results],
        "Valor_Variavel_Fluxo" => [r.valor_variavel_fluxo for r in team_flow_results],
        "Tipo_UBS" => [r.tipo_ubs for r in team_flow_results]
    )
    
    # Adicionar coluna de total de equipes (CNES + fluxo)
    df[!, "Total_Equipes"] = df.Quantidade_Equipes_CNES .+ df.Valor_Variavel_Fluxo
    
    # Salvar no Excel
    XLSX.writetable(filename, df)
    
    println("Tabela de fluxo de equipes salva com sucesso!")
    println("Resumo dos resultados:")
    println("  - Total de combinações UBS-Equipe: ", nrow(df))
    println("  - UBSs reais: ", count(df.Tipo_UBS .== "Real"))
    println("  - UBSs candidatas: ", count(df.Tipo_UBS .== "Candidata"))
    println("  - Total de equipes CNES: ", sum(df.Quantidade_Equipes_CNES))
    println("  - Total de equipes adicionais (fluxo): ", sum(df.Valor_Variavel_Fluxo))
    println("  - Total geral de equipes: ", sum(df.Total_Equipes))
    
    return df
end

"""
Adiciona os resultados do fluxo de equipes a uma aba existente do Excel
"""
function add_team_flow_to_excel(team_flow_results::Vector{TeamFlowResults}, 
                               filename::String)
    println("Adicionando resultados do fluxo de equipes ao arquivo: ", filename)
    
    # Criar DataFrame com os resultados
    df = DataFrame(
        "UBS" => [r.ubs for r in team_flow_results],
        "Quantidade_Equipes_CNES" => [r.quantidade_equipes_cnes for r in team_flow_results],
        "Valor_Variavel_Fluxo" => [r.valor_variavel_fluxo for r in team_flow_results],
        "Tipo_UBS" => [r.tipo_ubs for r in team_flow_results]
    )
    
    # Adicionar coluna de total de equipes (CNES + fluxo)
    df[!, "Total_Equipes"] = df.Quantidade_Equipes_CNES .+ df.Valor_Variavel_Fluxo
    
    # Abrir arquivo Excel existente e adicionar nova aba
    XLSX.openxlsx(filename, mode="rw") do xf
        # Verificar se a aba já existe

            # Se não existir, criar nova aba
        sheet = XLSX.addsheet!(xf, "Fluxo_Equipes")

        
        # Escrever cabeçalhos
        sheet["A1"] = "UBS"
        sheet["B1"] = "Quantidade_Equipes_CNES"
        sheet["C1"] = "Valor_Variavel_Fluxo"
        sheet["D1"] = "Tipo_UBS"
        sheet["E1"] = "Total_Equipes"
        
        # Escrever dados
        for (i, row) in enumerate(eachrow(df))
            sheet["A$(i+1)"] = row.UBS
            sheet["B$(i+1)"] = row.Quantidade_Equipes_CNES
            sheet["C$(i+1)"] = row.Valor_Variavel_Fluxo
            sheet["D$(i+1)"] = row.Tipo_UBS
            sheet["E$(i+1)"] = row.Total_Equipes
        end
    end
    
    println("Aba 'Fluxo_Equipes' adicionada com sucesso!")
    println("Resumo dos resultados:")
    println("  - Total de combinações UBS-Equipe: ", nrow(df))
    println("  - UBSs reais: ", count(df.Tipo_UBS .== "Real"))
    println("  - UBSs candidatas: ", count(df.Tipo_UBS .== "Candidata"))
    println("  - Total de equipes CNES: ", sum(df.Quantidade_Equipes_CNES))
    println("  - Total de equipes adicionais (fluxo): ", sum(df.Valor_Variavel_Fluxo))
    println("  - Total geral de equipes: ", sum(df.Total_Equipes))
    
    return df
end

"""
Adiciona os resultados dos custos a uma aba existente do Excel
"""
function add_cost_results_to_excel(cost_results::Vector{CostResults}, 
                                 filename::String)
    println("Adicionando resultados dos custos ao arquivo: ", filename)
    
    # Criar DataFrame com os resultados
    df = DataFrame(
        "Nivel" => [r.nivel for r in cost_results],
        "Tipo_Custo" => [r.tipo_custo for r in cost_results],
        "Valor_R" => [r.valor for r in cost_results],
        "Percentual" => [r.percentual for r in cost_results],
        "Descricao" => [r.descricao for r in cost_results]
    )
    
    # Abrir arquivo Excel existente e adicionar nova aba
    XLSX.openxlsx(filename, mode="rw") do xf
        # Verificar se a aba já existe

            # Se não existir, criar nova aba
        sheet = XLSX.addsheet!(xf, "Custos")

        
        # Escrever cabeçalhos
        sheet["A1"] = "Nivel"
        sheet["B1"] = "Tipo_Custo"
        sheet["C1"] = "Valor_R"
        sheet["D1"] = "Percentual"
        sheet["E1"] = "Descricao"
        
        # Escrever dados
        for (i, row) in enumerate(eachrow(df))
            sheet["A$(i+1)"] = row.Nivel
            sheet["B$(i+1)"] = row.Tipo_Custo
            sheet["C$(i+1)"] = row.Valor_R
            sheet["D$(i+1)"] = row.Percentual
            sheet["E$(i+1)"] = row.Descricao
        end
    end
    
    println("Aba 'Custos' adicionada com sucesso!")
    println("Resumo dos custos:")
    println("  - Total de tipos de custo: ", nrow(df))
    #println("  - Custo total: R$ ", round(sum(df.Valor_R), digits=2))
    
    # Mostrar os principais custos
    return df
end

function print_parcelas_funcao_objetivo(model)
    println("="^60)
    println("PARCELAS DA FUNCAO OBJETIVO")
    println("="^60)
    
    # Parcelas por nível
    println("\nCUSTOS POR NIVEL:")
    println("-"^40)
    
    # Nível 1 (Primário)

    
    # Nível 2 (Secundário)
    println("\nNIVEL SECUNDARIO:")
    println("  • Custo Logistico N2: R\$ " * string(round(value(model[:custo_logistico_n2]), digits=2)))
    println("  • Custo Fixo Existente N2: R\$ " * string(round(value(model[:custo_fixo_existente_n2]), digits=2)))
    println("  • Custo Equipes Novas N2: R\$ " * string(round(value(model[:custo_times_novos_n2]), digits=2)))
    println("  • Custo Variavel N2: R\$ " * string(round(value(model[:custo_variavel_n2]), digits=2)))
    
    # Nível 3 (Terciário)
    println("\nNIVEL TERCIARIO:")
    println("  • Custo Logistico N3: R\$ " * string(round(value(model[:custo_logistico_n3]), digits=2)))
    println("  • Custo Fixo Existente N3: R\$ " * string(round(value(model[:custo_fixo_existente_n3]), digits=2)))
    println("  • Custo Equipes Novas N3: R\$ " * string(round(value(model[:custo_times_novos_n3]), digits=2)))
    println("  • Custo Variavel N3: R\$ " * string(round(value(model[:custo_variavel_n3]), digits=2)))
    
    # Custos agregados
    println("\nCUSTOS AGREGADOS:")
    println("-"^40)
    println("  • Custo Logistico Total: R\$ " * string(round(value(model[:custo_logistico]), digits=2)))
    println("  • Custo Fixo Novo Total: R\$ " * string(round(value(model[:custo_fixo_novo]), digits=2)))
    println("  • Custo Fixo Existente Total: R\$ " * string(round(value(model[:custo_fixo_existente]), digits=2)))
    println("  • Custo Equipes Novas Total: R\$ " * string(round(value(model[:custo_times_novos]), digits=2)))
    println("  • Custo Variavel Total: R\$ " * string(round(value(model[:custo_variavel]), digits=2)))
    
    # Custo total
    println("\nCUSTO TOTAL:")
    println("-"^40)
    custo_total = value(model[:custo_logistico]) + 
                  value(model[:custo_fixo_novo]) + 
                  value(model[:custo_fixo_existente]) + 
                  value(model[:custo_times_novos]) + 
                  value(model[:custo_variavel])
    println("  • Custo Total: R\$ " * string(round(custo_total, digits=2)))
    
    # Percentuais de cada parcela
    println("\nPERCENTUAIS DE CADA PARCELA:")
    println("-"^40)
    println("  • Custo Logistico: " * string(round(100 * value(model[:custo_logistico]) / custo_total, digits=1)) * "%")
    println("  • Custo Fixo Novo: " * string(round(100 * value(model[:custo_fixo_novo]) / custo_total, digits=1)) * "%")
    println("  • Custo Fixo Existente: " * string(round(100 * value(model[:custo_fixo_existente]) / custo_total, digits=1)) * "%")
    println("  • Custo Equipes Novas: " * string(round(100 * value(model[:custo_times_novos]) / custo_total, digits=1)) * "%")
    println("  • Custo Variavel: " * string(round(100 * value(model[:custo_variavel]) / custo_total, digits=1)) * "%")
    
    println("\n" * "="^60)
end

# Função para imprimir detalhes das variáveis de decisão
function print_variaveis_decisao(model)
    println("\nVARIAVEIS DE DECISAO:")
    println("-"^40)
    
    # Unidades abertas
    println("\nUNIDADES ABERTAS:")
    println("  • Nivel 1: " * string(sum(value.(model[:Abr_n1]))) * " unidades")
    println("  • Nivel 2: " * string(sum(value.(model[:Abr_n2]))) * " unidades")
    println("  • Nivel 3: " * string(sum(value.(model[:Abr_n3]))) * " unidades")
    
    # Equipes alocadas
    println("\nEQUIPES ALOCADAS:")
    println("  • Nivel 1: " * string(sum(value.(model[:eq_n1]))) * " equipes")
    println("  • Nivel 2: " * string(sum(value.(model[:eq_n2]))) * " equipes")
    println("  • Nivel 3: " * string(sum(value.(model[:eq_n3]))) * " equipes")
end

# Função para gerar arquivo Excel com dados da função objetivo
function gerar_excel_funcao_objetivo(model, nome_arquivo="resultados_funcao_objetivo.xlsx")
    # Coletar todos os dados
    dados = Dict()
    
    # Custos por nível
    dados["custo_logistico_n1"] = round(value(model[:custo_logistico_n1]), digits=2)
    dados["custo_fixo_novos_n1"] = round(value(model[:custo_fixo_novos_n1]), digits=2)
    dados["custo_fixo_existente_n1"] = round(value(model[:custo_fixo_existente_n1]), digits=2)
    dados["custo_times_novos_n1"] = round(value(model[:custo_times_novos_n1]), digits=2)
    dados["custo_variavel_n1"] = round(value(model[:custo_variavel_n1]), digits=2)
    
    dados["custo_logistico_n2"] = round(value(model[:custo_logistico_n2]), digits=2)
    dados["custo_fixo_existente_n2"] = round(value(model[:custo_fixo_existente_n2]), digits=2)
    dados["custo_times_novos_n2"] = round(value(model[:custo_times_novos_n2]), digits=2)
    dados["custo_variavel_n2"] = round(value(model[:custo_variavel_n2]), digits=2)
    
    dados["custo_logistico_n3"] = round(value(model[:custo_logistico_n3]), digits=2)
    dados["custo_fixo_existente_n3"] = round(value(model[:custo_fixo_existente_n3]), digits=2)
    dados["custo_times_novos_n3"] = round(value(model[:custo_times_novos_n3]), digits=2)
    dados["custo_variavel_n3"] = round(value(model[:custo_variavel_n3]), digits=2)
    
    # Custos agregados
    dados["custo_logistico_total"] = round(value(model[:custo_logistico]), digits=2)
    dados["custo_fixo_novo_total"] = round(value(model[:custo_fixo_novo]), digits=2)
    dados["custo_fixo_existente_total"] = round(value(model[:custo_fixo_existente]), digits=2)
    dados["custo_times_novos_total"] = round(value(model[:custo_times_novos]), digits=2)
    dados["custo_variavel_total"] = round(value(model[:custo_variavel]), digits=2)
    
    # Custo total
    custo_total = value(model[:custo_logistico]) + 
                  value(model[:custo_fixo_novo]) + 
                  value(model[:custo_fixo_existente]) + 
                  value(model[:custo_times_novos]) + 
                  value(model[:custo_variavel])
    dados["custo_total"] = round(custo_total, digits=2)
    
    # Percentuais
    dados["perc_logistico"] = round(100 * value(model[:custo_logistico]) / custo_total, digits=1)
    dados["perc_fixo_novo"] = round(100 * value(model[:custo_fixo_novo]) / custo_total, digits=1)
    dados["perc_fixo_existente"] = round(100 * value(model[:custo_fixo_existente]) / custo_total, digits=1)
    dados["perc_equipes_novas"] = round(100 * value(model[:custo_times_novos]) / custo_total, digits=1)
    dados["perc_variavel"] = round(100 * value(model[:custo_variavel]) / custo_total, digits=1)
    
    # Variáveis de decisão
    dados["unidades_abertas_n1"] = sum(value.(model[:Abr_n1]))
    dados["unidades_abertas_n2"] = sum(value.(model[:Abr_n2]))
    dados["unidades_abertas_n3"] = sum(value.(model[:Abr_n3]))
    dados["equipes_alocadas_n1"] = sum(value.(model[:eq_n1]))
    dados["equipes_alocadas_n2"] = sum(value.(model[:eq_n2]))
    dados["equipes_alocadas_n3"] = sum(value.(model[:eq_n3]))
    
    # Criar arquivo Excel
    XLSX.openxlsx(nome_arquivo, mode="w") do xf
        # Planilha 1: Custos por Nível
        sheet1 = xf[1]
        sheet1.name = "Custos por Nivel"
        
        # Adicionar novas planilhas
        sheet2 = XLSX.addsheet!(xf, "Custos Agregados")
        sheet3 = XLSX.addsheet!(xf, "Variaveis Decisao")
        sheet4 = XLSX.addsheet!(xf, "Resumo Executivo")
        
        # Cabeçalhos
        sheet1["A1"] = "Nivel"
        sheet1["B1"] = "Tipo de Custo"
        sheet1["C1"] = "Valor (R\$)"
        sheet1["D1"] = "Descricao"
        
        # Dados Nível 1
        sheet1["A2"] = "Primario"
        sheet1["B2"] = "Logistico"
        sheet1["C2"] = dados["custo_logistico_n1"]
        sheet1["D2"] = "Custo de transporte nível primário"
        
        sheet1["A3"] = "Primario"
        sheet1["B3"] = "Fixo Novos"
        sheet1["C3"] = dados["custo_fixo_novos_n1"]
        sheet1["D3"] = "Custo de abertura de novas unidades"
        
        sheet1["A4"] = "Primario"
        sheet1["B4"] = "Fixo Existente"
        sheet1["C4"] = dados["custo_fixo_existente_n1"]
        sheet1["D4"] = "Custo fixo das unidades existentes"
        
        sheet1["A5"] = "Primario"
        sheet1["B5"] = "Equipes Novas"
        sheet1["C5"] = dados["custo_times_novos_n1"]
        sheet1["D5"] = "Custo das novas equipes"
        
        sheet1["A6"] = "Primario"
        sheet1["B6"] = "Variavel"
        sheet1["C6"] = dados["custo_variavel_n1"]
        sheet1["D6"] = "Custo variável por paciente"
        
        # Dados Nível 2
        sheet1["A7"] = "Secundario"
        sheet1["B7"] = "Logistico"
        sheet1["C7"] = dados["custo_logistico_n2"]
        sheet1["D7"] = "Custo de transporte nível secundário"
        
        sheet1["A8"] = "Secundario"
        sheet1["B8"] = "Fixo Existente"
        sheet1["C8"] = dados["custo_fixo_existente_n2"]
        sheet1["D8"] = "Custo fixo das unidades existentes"
        
        sheet1["A9"] = "Secundario"
        sheet1["B9"] = "Equipes Novas"
        sheet1["C9"] = dados["custo_times_novos_n2"]
        sheet1["D9"] = "Custo das novas equipes"
        
        sheet1["A10"] = "Secundario"
        sheet1["B10"] = "Variavel"
        sheet1["C10"] = dados["custo_variavel_n2"]
        sheet1["D10"] = "Custo variável por paciente"
        
        # Dados Nível 3
        sheet1["A11"] = "Terciario"
        sheet1["B11"] = "Logistico"
        sheet1["C11"] = dados["custo_logistico_n3"]
        sheet1["D11"] = "Custo de transporte nível terciário"
        
        sheet1["A12"] = "Terciario"
        sheet1["B12"] = "Fixo Existente"
        sheet1["C12"] = dados["custo_fixo_existente_n3"]
        sheet1["D12"] = "Custo fixo das unidades existentes"
        
        sheet1["A13"] = "Terciario"
        sheet1["B13"] = "Equipes Novas"
        sheet1["C13"] = dados["custo_times_novos_n3"]
        sheet1["D13"] = "Custo das novas equipes"
        
        sheet1["A14"] = "Terciario"
        sheet1["B14"] = "Variavel"
        sheet1["C14"] = dados["custo_variavel_n3"]
        sheet1["D14"] = "Custo variável por paciente"
        
        # Planilha 2: Custos Agregados (já criada acima)
        
        sheet2["A1"] = "Tipo de Custo"
        sheet2["B1"] = "Valor (R\$)"
        sheet2["C1"] = "Percentual (%)"
        sheet2["D1"] = "Descricao"
        
        sheet2["A2"] = "Logistico Total"
        sheet2["B2"] = dados["custo_logistico_total"]
        sheet2["C2"] = dados["perc_logistico"]
        sheet2["D2"] = "Custo total de transporte"
        
        sheet2["A3"] = "Fixo Novo Total"
        sheet2["B3"] = dados["custo_fixo_novo_total"]
        sheet2["C3"] = dados["perc_fixo_novo"]
        sheet2["D3"] = "Custo total de abertura de novas unidades"
        
        sheet2["A4"] = "Fixo Existente Total"
        sheet2["B4"] = dados["custo_fixo_existente_total"]
        sheet2["C4"] = dados["perc_fixo_existente"]
        sheet2["D4"] = "Custo fixo total das unidades existentes"
        
        sheet2["A5"] = "Equipes Novas Total"
        sheet2["B5"] = dados["custo_times_novos_total"]
        sheet2["C5"] = dados["perc_equipes_novas"]
        sheet2["D5"] = "Custo total das novas equipes"
        
        sheet2["A6"] = "Variavel Total"
        sheet2["B6"] = dados["custo_variavel_total"]
        sheet2["C6"] = dados["perc_variavel"]
        sheet2["D6"] = "Custo variável total por paciente"
        
        sheet2["A7"] = "CUSTO TOTAL"
        sheet2["B7"] = dados["custo_total"]
        sheet2["C7"] = 100.0
        sheet2["D7"] = "Custo total do sistema"
        
        # Planilha 3: Variáveis de Decisão (já criada acima)
        
        sheet3["A1"] = "Nivel"
        sheet3["B1"] = "Tipo"
        sheet3["C1"] = "Quantidade"
        sheet3["D1"] = "Descricao"
        
        sheet3["A2"] = "Primario"
        sheet3["B2"] = "Unidades Abertas"
        sheet3["C2"] = dados["unidades_abertas_n1"]
        sheet3["D2"] = "Número de unidades do nível primário abertas"
        
        sheet3["A3"] = "Secundario"
        sheet3["B3"] = "Unidades Abertas"
        sheet3["C3"] = dados["unidades_abertas_n2"]
        sheet3["D3"] = "Número de unidades do nível secundário abertas"
        
        sheet3["A4"] = "Terciario"
        sheet3["B4"] = "Unidades Abertas"
        sheet3["C4"] = dados["unidades_abertas_n3"]
        sheet3["D4"] = "Número de unidades do nível terciário abertas"
        
        sheet3["A5"] = "Primario"
        sheet3["B5"] = "Equipes Alocadas"
        sheet3["C5"] = dados["equipes_alocadas_n1"]
        sheet3["D5"] = "Número de equipes alocadas no nível primário"
        
        sheet3["A6"] = "Secundario"
        sheet3["B6"] = "Equipes Alocadas"
        sheet3["C6"] = dados["equipes_alocadas_n2"]
        sheet3["D6"] = "Número de equipes alocadas no nível secundário"
        
        sheet3["A7"] = "Terciario"
        sheet3["B7"] = "Equipes Alocadas"
        sheet3["C7"] = dados["equipes_alocadas_n3"]
        sheet3["D7"] = "Número de equipes alocadas no nível terciário"
        
        # Planilha 4: Resumo Executivo (já criada acima)
        
        sheet4["A1"] = "RESUMO EXECUTIVO"
        sheet4["A2"] = "Custo Total do Sistema"
        sheet4["B2"] = dados["custo_total"]
        sheet4["C2"] = "R\$"
        
        sheet4["A4"] = "Maior Componente de Custo"
        maior_custo = maximum([dados["perc_logistico"], dados["perc_fixo_novo"], 
                              dados["perc_fixo_existente"], dados["perc_equipes_novas"], 
                              dados["perc_variavel"]])
        
        if maior_custo == dados["perc_logistico"]
            sheet4["B4"] = "Custo Logístico"
            sheet4["C4"] = string(dados["perc_logistico"]) * "%"
        elseif maior_custo == dados["perc_fixo_novo"]
            sheet4["B4"] = "Custo Fixo Novo"
            sheet4["C4"] = string(dados["perc_fixo_novo"]) * "%"
        elseif maior_custo == dados["perc_fixo_existente"]
            sheet4["B4"] = "Custo Fixo Existente"
            sheet4["C4"] = string(dados["perc_fixo_existente"]) * "%"
        elseif maior_custo == dados["perc_equipes_novas"]
            sheet4["B4"] = "Custo Equipes Novas"
            sheet4["C4"] = string(dados["perc_equipes_novas"]) * "%"
        else
            sheet4["B4"] = "Custo Variável"
            sheet4["C4"] = string(dados["perc_variavel"]) * "%"
        end
        
        sheet4["A6"] = "Total de Unidades Abertas"
        sheet4["B6"] = dados["unidades_abertas_n1"] + dados["unidades_abertas_n2"] + dados["unidades_abertas_n3"]
        
        sheet4["A7"] = "Total de Equipes Alocadas"
        sheet4["B7"] = dados["equipes_alocadas_n1"] + dados["equipes_alocadas_n2"] + dados["equipes_alocadas_n3"]
    end
    
    println("Arquivo Excel gerado com sucesso: " * nome_arquivo)
    println("Planilhas criadas:")
    println("  1. Custos por Nivel")
    println("  2. Custos Agregados") 
    println("  3. Variaveis Decisao")
    println("  4. Resumo Executivo")
end


function create_optimization_model_maximal_coverage(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

    # Extrair dados para facilitar a leitura e escrita do modelo!
    S_n1 = indices.S_n1
    S_n2 = indices.S_n2
    S_n3 = indices.S_n3
    S_locais_candidatos_n1 = indices.S_Locais_Candidatos_n1
    S_instalacoes_reais_n1 = indices.S_instalacoes_reais_n1
    S_instalacoes_reais_n2 = indices.S_instalacoes_reais_n2
    S_instalacoes_reais_n3 = indices.S_instalacoes_reais_n3
    S_Pontos_Demanda = indices.S_Pontos_Demanda
    S_equipes = indices.S_equipes_n1
    S_equipes_n2 = indices.S_equipes_n2
    S_equipes_n3 = indices.S_equipes_n3
    S_pacientes =  mun_data.constantes.S_pacientes
    S_Valor_Demanda = mun_data.S_Valor_Demanda
    porcentagem_populacao = mun_data.constantes.porcentagem_populacao
    S_IVS = parameters.IVS

    dominio_atr_n1 = parameters.S_domains.dominio_n1

    #TODO: Retomar workarround de locais candidatos que atendam os pontos sem nenhum opcao no raio critico!
    dominio_candidatos_n1 = Dict(d => [s for s in dominio_atr_n1[d] if s in S_locais_candidatos_n1] for d in keys(dominio_atr_n1))

    dominio_atr_n2 = parameters.S_domains.dominio_n2
    dominio_atr_n3 = parameters.S_domains.dominio_n3
    
    percent_n1_n2 = mun_data.constantes.percent_n1_n2
    percent_n2_n3 = mun_data.constantes.percent_n2_n3

    Cap_n1 = mun_data.constantes.Cap_n1
    Cap_n2 = mun_data.constantes.Cap_n2
    Cap_n3 = mun_data.constantes.Cap_n3


    capacidade_maxima_por_equipe_n1 = parameters.capacidade_maxima_por_equipe_n1
    capacidade_maxima_por_equipe_n2 = parameters.S_eq_por_paciente_n2
    capacidade_maxima_por_equipe_n3 = parameters.S_eq_por_paciente_n3

    S_custo_equipe_n1 = parameters.S_custo_equipe_n1
    S_custo_equipe_n2 = parameters.S_custo_equipe_n2
    S_custo_equipe_n3 = parameters.S_custo_equipe_n3

    S_capacidade_CNES_n1 = parameters.S_capacidade_CNES_n1
    S_capacidade_CNES_n1 = vcat(S_capacidade_CNES_n1, [0.0,0.0])
    S_capacidade_CNES_n2 = parameters.S_capacidade_CNES_n2
    S_capacidade_CNES_n3 = parameters.S_capacidade_CNES_n3

    Matriz_Dist_n1 = parameters.S_Matriz_Dist.Matriz_Dist_n1
    Matriz_Dist_n2 = parameters.S_Matriz_Dist.Matriz_Dist_n2
    Matriz_Dist_n3 = parameters.S_Matriz_Dist.Matriz_Dist_n3

    custo_deslocamento = mun_data.constantes.custo_transporte  
    Custo_abertura_n1 = mun_data.constantes.custo_abertura_n1
    Custo_abertura_n2 = mun_data.constantes.custo_abertura_n2
    Custo_abertura_n3 = mun_data.constantes.custo_abertura_n3

    S_custo_variavel_n1 = mun_data.constantes.S_custo_variavel_n1
    S_custo_variavel_n2 = mun_data.constantes.S_custo_variavel_n2
    S_custo_variavel_n3 = mun_data.constantes.S_custo_variavel_n3

    S_custo_fixo_n1 = mun_data.constantes.S_custo_fixo_n1
    S_custo_fixo_n2 = mun_data.constantes.S_custo_fixo_n2
    S_custo_fixo_n3 = mun_data.constantes.S_custo_fixo_n3

    S_quantidade_total_real_equipes = Vector{Int64}([sum(S_capacidade_CNES_n1[:,eq]) for eq in S_equipes])
    Orcamento_Maximo = parameters.orcamento_maximo
    ponderador_Vulnerabilidade = parameters.ponderador_Vulnerabilidade
    S_IVS = ponderador_Vulnerabilidade .* parameters.IVS

    cap_equipes_n1 = 3000

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", 300.0)
    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-6) 
    set_optimizer_attribute(model, "mip_rel_gap", 0.02) 
    #Variaveis

    #atribuicao primária
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin) #Abertura unidades primárias
    fluxo_eq_n1 = @variable(model, eq_n1[eq in S_equipes, n1 in S_n1])
    var_pop_atendida = @variable(model, pop_atendida[d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]] >= 0) #Inserir aqui as demografias das populacoes!
    
    #inicialmente vou somente encaminhar demanda para niveis superiore
    #Fluxo n2
    fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1]] >= 0)
    var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
    #Fluxo n3
    fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2]] >= 0)
    var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)

    #Todas as unidades devem ser alocadas numa UBS de referencia
    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) == 1)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] * maximum(S_Valor_Demanda))
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d])
    


    #Capacidades das UBS de acordo com a quantidade de equipes alocadas
    @constraint(model, [n1 in S_instalacoes_reais_n1, eq in S_equipes], 
    sum(var_pop_atendida[d, eq, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) <= (S_capacidade_CNES_n1[n1, eq] + fluxo_eq_n1[eq,n1]) * cap_equipes_n1)

    @constraint(model, [n1 in S_locais_candidatos_n1, eq in S_equipes], 
    sum(var_pop_atendida[d, eq, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) <=  fluxo_eq_n1[eq,n1] * cap_equipes_n1)

    #Abertura de unidades novas:
    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], 
                         Aloc_[d, s] <= var_abr_n1[s] )

    #Restricao do fluxo de equipes:
    #@constraint(model, [eq in S_equipes, un in S_instalacoes_reais_n1], 
    #S_capacidade_CNES_n1[un, eq] + fluxo_eq_n1[eq,un] == sum(pop_atendida[d, eq, un] for d in S_Pontos_Demanda if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])


    #@constraint(model, [eq in S_equipes, un in S_locais_candidatos_n1], 
        #fluxo_eq_n1[eq,un] == sum(pop_atendida[d, eq, un] for d in S_Pontos_Demanda if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])

    
    #Restricao de balanco de massa de capacidade
    #@constraint(model, [eq in S_equipes], 
    #sum(S_capacidade_CNES_n1[un, eq] + fluxo_eq_n1[eq,un] for un in S_instalacoes_reais_n1) <= S_quantidade_total_real_equipes[eq])

    #@constraint(model, [n1 in S_n1, eq in S_equipes],
                     #  sum(pop_atendida[d, eq, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
                      # >= var_equidade[eq] * sum(S_Valor_Demanda[d] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))
    #Limitacao de Orcamentos

    #@expression(model, custo_logistico_n1,  sum(X_n1[d, un, p] * Matriz_Dist_n1[d, un] * custo_deslocamento for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))

    @expression(model, custo_fixo_novos_n1, sum(Abr_n1[un] * S_custo_fixo_n1 for un in S_locais_candidatos_n1))
    #@expression(model, custo_fixo_existente_n1, sum(S_custo_fixo_n1 for un1 in S_instalacoes_reais_n1))
    @expression(model, custo_times_novos_n1, sum(fluxo_eq_n1[eq, un] * S_custo_equipe_n1[eq] for eq in S_equipes, un in S_n1))
    @expression(model, custo_variavel_n1, sum(pop_atendida[d, eq,  un] * S_custo_variavel_n1[1] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d]))
    @expression(model, custo_total_n1, custo_fixo_novos_n1 
   # + custo_fixo_existente_n1 
    + custo_times_novos_n1 
    + custo_variavel_n1)


    @constraint(model, custo_total_n1 <= Orcamento_Maximo)


    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
                sum(X_n2[n1, n2] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(pop_atendida[d, eq, n1] 
                        for  eq in S_equipes, d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))


    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
            sum(X_n3[n2, n3] for n3 in dominio_atr_n3[n2]) == 
            percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in dominio_atr_n2[n1]))
                    

    #Funcao Objetivo:
    @objective(model, Max, sum(pop_atendida[d, eq, un] * S_IVS[d] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d]) 
    #+ sum(var_equidade[eq] * vls_eq[eq] for eq in S_equipes)
    )

    #optimize!(model)
    #obj = objective_value(model)
    #println(obj)
    #println(value(custo_total_n1))
    return model

end


function create_optimization_model_maximal_coverage_per_equipes(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model
    S_n1 = indices.S_n1
    S_n2 = indices.S_n2
    S_n3 = indices.S_n3
    S_locais_candidatos_n1 = indices.S_Locais_Candidatos_n1
    S_instalacoes_reais_n1 = indices.S_instalacoes_reais_n1
    S_instalacoes_reais_n2 = indices.S_instalacoes_reais_n2
    S_instalacoes_reais_n3 = indices.S_instalacoes_reais_n3
    S_Pontos_Demanda = indices.S_Pontos_Demanda
    S_equipes = indices.S_equipes_n1
    S_equipes_n2 = indices.S_equipes_n2
    S_equipes_n3 = indices.S_equipes_n3
    S_pacientes =  mun_data.constantes.S_pacientes
    S_Valor_Demanda = mun_data.S_Valor_Demanda
    porcentagem_populacao = mun_data.constantes.porcentagem_populacao
    S_IVS = parameters.IVS

    dominio_atr_n1 = parameters.S_domains.dominio_n1

    #TODO: Retomar workarround de locais candidatos que atendam os pontos sem nenhum opcao no raio critico!
    dominio_candidatos_n1 = Dict(d => [s for s in dominio_atr_n1[d] if s in S_locais_candidatos_n1] for d in keys(dominio_atr_n1))

    dominio_atr_n2 = parameters.S_domains.dominio_n2
    dominio_atr_n3 = parameters.S_domains.dominio_n3
    
    percent_n1_n2 = mun_data.constantes.percent_n1_n2
    percent_n2_n3 = mun_data.constantes.percent_n2_n3

    Cap_n1 = mun_data.constantes.Cap_n1
    Cap_n2 = mun_data.constantes.Cap_n2
    Cap_n3 = mun_data.constantes.Cap_n3


    capacidade_maxima_por_equipe_n1 = parameters.capacidade_maxima_por_equipe_n1
    capacidade_maxima_por_equipe_n2 = parameters.S_eq_por_paciente_n2
    capacidade_maxima_por_equipe_n3 = parameters.S_eq_por_paciente_n3

    S_custo_equipe_n1 = parameters.S_custo_equipe_n1
    S_custo_equipe_n2 = parameters.S_custo_equipe_n2
    S_custo_equipe_n3 = parameters.S_custo_equipe_n3

    S_capacidade_CNES_n1 = parameters.S_capacidade_CNES_n1
    S_capacidade_CNES_n2 = parameters.S_capacidade_CNES_n2
    S_capacidade_CNES_n3 = parameters.S_capacidade_CNES_n3

    Matriz_Dist_n1 = parameters.S_Matriz_Dist.Matriz_Dist_n1
    Matriz_Dist_n2 = parameters.S_Matriz_Dist.Matriz_Dist_n2
    Matriz_Dist_n3 = parameters.S_Matriz_Dist.Matriz_Dist_n3

    custo_deslocamento = mun_data.constantes.custo_transporte  
    Custo_abertura_n1 = mun_data.constantes.custo_abertura_n1
    Custo_abertura_n2 = mun_data.constantes.custo_abertura_n2
    Custo_abertura_n3 = mun_data.constantes.custo_abertura_n3

    S_custo_variavel_n1 = mun_data.constantes.S_custo_variavel_n1
    S_custo_variavel_n2 = mun_data.constantes.S_custo_variavel_n2
    S_custo_variavel_n3 = mun_data.constantes.S_custo_variavel_n3

    S_custo_fixo_n1 = mun_data.constantes.S_custo_fixo_n1
    S_custo_fixo_n2 = mun_data.constantes.S_custo_fixo_n2
    S_custo_fixo_n3 = mun_data.constantes.S_custo_fixo_n3

    S_quantidade_total_real_equipes = Vector{Int64}([sum(S_capacidade_CNES_n1[:,eq]) for eq in S_equipes])
    vls_eq = [100, 200, 300, 100, 20, 40, 50, 70, 90, 30, 11]
    Orcamento_Maximo = 200000000


    #Novo metodo das equipes
    eqs_ESF = [23, 70, 76, 72, 22, 1]
    equipes_ESF_filtradas = filter(row -> row.TP_EQUIPE in eqs_ESF && row.ST_ATIVA == 1, mun_data.equipes_primario_v2)
    
    # Garantir ordem correspondente entre códigos e capacidades
    # Opção 1: Usar vetores paralelos (mais simples)
    CNES_Equipes_n1 = [row.CO_EQUIPE for row in eachrow(equipes_ESF_filtradas)] #Lista com codigo de cada equipe!
    Cap_Equipes_n1 = [row.PARAMETRO_CADASTRAL for row in eachrow(equipes_ESF_filtradas)] #Capacidade da equipe!
    S_qntd_Equipes_reais = length(CNES_Equipes_n1)
    S_Equipes_Reais_n1 = collect(1:S_qntd_Equipes_reais)
    S_equipes_candidatas = collect(S_qntd_Equipes_reais + 1: S_qntd_Equipes_reais + 30)
    S_Equipes_n1 = collect(1: S_qntd_Equipes_reais + 30)
    S_cap_equipes_candidadatas = fill(3000, length(S_equipes_candidatas))
    S_cap_equipes_final = vcat(Cap_Equipes_n1, S_cap_equipes_candidadatas)

    pontos_sem_cobertura = [d for d in S_Pontos_Demanda if isempty(dominio_atr_n1[d])]

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", 3600.0)
    # --- variáveis (mantendo seus nomes) ---
    @variable(model, Atend_D_E_Ubs[d in S_Pontos_Demanda,
                                eq in S_Equipes_n1,
                                n1 in dominio_atr_n1[d]], Bin)

    @variable(model, Aloc_E_Ubs[eq in S_Equipes_n1, n1 in S_n1], Bin)

    @variable(model, Aloc_Ubs[n1 in S_n1], Bin)

    # agora pop_atendida é >= 0 (use Int se quiser contar pessoas inteiras)
    @variable(model, pop_atendida[d in S_Pontos_Demanda,
                                eq in S_Equipes_n1,
                                n1 in dominio_atr_n1[d]] >= 0)

    # (suas variáveis de abertura / equipes extras seguem iguais)
    @variable(model, var_abr_n1[n1 in S_n1], Bin)
    @variable(model, var_eqs_extras[eq in S_equipes_candidatas] >= 0, Int)
    

    # um ponto pode ser atendido por no máximo UMA equipe/UBS
    @constraint(model, [d in S_Pontos_Demanda],
        sum(Atend_D_E_Ubs[d, eq, n1] for eq in S_Equipes_n1, n1 in dominio_atr_n1[d]) <= 1)


    @constraint(model, [d in S_Pontos_Demanda, eq in S_Equipes_n1, n1 in dominio_atr_n1[d]],
        Atend_D_E_Ubs[d, eq, n1] <= Aloc_E_Ubs[eq, n1])


    @constraint(model, [d in S_Pontos_Demanda, eq in S_Equipes_n1, n1 in dominio_atr_n1[d]],
        pop_atendida[d, eq, n1] <= S_Valor_Demanda[d] * Atend_D_E_Ubs[d, eq, n1])

    # (5) opcional: também é conveniente forçar pop_atendida <= S_Valor_Demanda (redundante, mas claro)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_Equipes_n1, n1 in dominio_atr_n1[d]],
        pop_atendida[d, eq, n1] <= S_Valor_Demanda[d])

    # (6) capacidade por equipe usando pop_atendida
    @constraint(model, [eq in S_Equipes_n1],
        sum(pop_atendida[d, eq, n1] for d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]) <= S_cap_equipes_final[eq])

    # (7) abertura de UBS / equipes (mantém suas regras)
    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], 
                        sum(Atend_D_E_Ubs[d, s] for eq in S_Equipes_n1) <= var_abr_n1[s] * 100000)


    @constraint(model, [eq in S_equipes_candidatas, n1 in S_n1],
        Aloc_E_Ubs[eq, n1] <= var_eqs_extras[eq])
    
    # ---------------------------------------------------------
    @objective(model, Max,
    sum(pop_atendida[d, eq, un] * S_IVS[d]
        for d in S_Pontos_Demanda, eq in S_Equipes_n1, un in S_n1 if un in dominio_atr_n1[d]))
    # Otimizar
    optimize!(model)
    
    println("Objetivo = ", objective_value(model))
    for d in S_Pontos_Demanda, e in S_Equipes_n1, u in dominio_atr_n1[d]
        if value(Atend_D_E_Ubs[d,e,u]) > 0.5
            println("Demanda $d atendida pela equipe $e na UBS $u")
        end
    end
    for u in S_n1
        if value(Aloc_Ubs[u]) > 0.5
            println("UBS aberta: $u")
        end
    end 
    for e in S_equipes_candidatas
        println("Equipes_extra[$e] = ", value(Equipes_extra[e]))
    end

end


function diagnosticar_infeasibility(model, indices, mun_data, parameters)
    println("=== DIAGNÓSTICO DE INFEASIBILITY ===")
    
    # 1. Verificar domínios vazios
    println("\n1. Verificando domínios de atendimento:")
    pontos_sem_cobertura = []
    for d in indices.S_Pontos_Demanda
        if isempty(parameters.S_domains.dominio_n1[d])
            push!(pontos_sem_cobertura, d)
        end
    end
    
    if !isempty(pontos_sem_cobertura)
        println("❌ ERRO: Pontos sem cobertura: $pontos_sem_cobertura")
    else
        println("✅ Todos os pontos têm cobertura")
    end
    
    # 2. Verificar capacidade vs demanda
    println("\n2. Verificando capacidade vs demanda:")
    demanda_total = sum(mun_data.S_Valor_Demanda[d] for d in indices.S_Pontos_Demanda)
    capacidade_total = sum(mun_data.constantes.Cap_n1)
    println("Demanda total: $demanda_total")
    println("Capacidade total: $capacidade_total")
    
    if demanda_total > capacidade_total
        println("❌ ERRO: Demanda total excede capacidade total")
    else
        println("✅ Capacidade suficiente")
    end
    
    # 3. Verificar orçamento
    println("\n3. Verificando orçamento:")
    custo_minimo = sum(mun_data.constantes.S_custo_fixo_n1)
    println("Custo mínimo: $custo_minimo")
    println("Orçamento máximo: 2000000")
    
    if custo_minimo > 2000000
        println("❌ ERRO: Custo mínimo excede orçamento")
    else
        println("✅ Orçamento suficiente")
    end
    
    # 4. Verificar restrições de equipes
    println("\n4. Verificando restrições de equipes:")
    problemas_equipes = 0
    for eq in indices.S_equipes_n1
        for un in indices.S_instalacoes_reais_n1
            demanda_esperada = sum(mun_data.S_Valor_Demanda[d] for d in indices.S_Pontos_Demanda 
                                 if un in parameters.S_domains.dominio_n1[d])
            capacidade_necessaria = demanda_esperada * parameters.capacidade_maxima_por_equipe_n1[eq]
            capacidade_disponivel = parameters.S_capacidade_CNES_n1[un, eq]
            
            if capacidade_necessaria > capacidade_disponivel
                problemas_equipes += 1
                if problemas_equipes <= 5  # Mostrar apenas os primeiros 5
                    println("❌ Instalação $un, equipe $eq - Necessário: $capacidade_necessaria, Disponível: $capacidade_disponivel")
                end
            end
        end
    end
    
    if problemas_equipes > 0
        println("❌ Total de problemas de equipes: $problemas_equipes")
    else
        println("✅ Restrições de equipes OK")
    end
    
    return pontos_sem_cobertura, demanda_total > capacidade_total, custo_minimo > 2000000, problemas_equipes > 0
end