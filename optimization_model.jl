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
    populacao_atendida_total_eq_1::Float64
    populacao_atendida_total_eq_2::Float64
    populacao_atendida_total_ENASF_2::Float64
    ubs_alocada::Int
    coord_demanda_lat::Float64
    coord_demanda_lon::Float64
    coord_ubs_lat::Float64
    coord_ubs_lon::Float64
    ivs::Float64
    cnes::Int
    nome_fantasia::String
    distancia::Float64
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
    pop_atendida_enasf = value.(model[:pop_coberta_ENASF])
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
        
        # Calcular população total atendida (preciso saber por tipo de equipes!)
        populacao_atendida_total_eq_1 = 0.0
        populacao_atendida_total_eq_2 = 0.0
        populacao_atendida_total_ENASF_2 = 0.0

        for eq in indices.S_equipes_n1
            for n1 in indices.S_n1
                if haskey(pop_atendida_values, (d, eq, n1)) && pop_atendida_values[d, eq, n1] > 0
                    if eq == 1
                        populacao_atendida_total_eq_1 += pop_atendida_values[d, eq, n1]
                    end
                    if eq == 2
                        populacao_atendida_total_eq_2 += pop_atendida_values[d, eq, n1]
                    end
                end
            end
        end


        for n1 in indices.S_n1
            if haskey(pop_atendida_enasf, (d, n1)) && pop_atendida_enasf[d, n1] > 0
                populacao_atendida_total_ENASF_2 += pop_atendida_enasf[d, n1]
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
                cnes = ubs_row.cnes
                nome_fantasia = ubs_row.nome_fantasia
                distancia = parameters.S_Matriz_Dist.Matriz_Dist_n1[d, ubs_alocada]
            else
                # É uma UBS candidata (localizada no ponto de demanda)
                candidata_idx = ubs_alocada - length(mun_data.unidades_n1.cnes)
                if candidata_idx <= length(mun_data.coordenadas)
                    coord_ubs_lat = mun_data.coordenadas[candidata_idx][1]
                    coord_ubs_lon = mun_data.coordenadas[candidata_idx][2]
                    cnes = 000000
                    nome_fantasia = "Unidade_Candidata_Aberta"
                    distancia = parameters.S_Matriz_Dist.Matriz_Dist_n1[d, candidata_idx]
                end
            end
        else
            coord_ubs_lat = 0.0
            coord_ubs_lon = 0.0
            cnes = 99999999
            nome_fantasia = "Nao alocado"
            distancia = 0.0
        end
        
        # Criar resultado para este ponto de demanda
        result = PopulationResults(
            setor,
            d,                          # ponto_demanda
            populacao_total,            # populacao_total
            populacao_atendida_total_eq_1,
            populacao_atendida_total_eq_2,   # populacao_atendida
            populacao_atendida_total_ENASF_2, 
            ubs_alocada,                # ubs_alocada
            coord_demanda_lat,          # coord_demanda_lat
            coord_demanda_lon,          # coord_demanda_lon
            coord_ubs_lat,              # coord_ubs_lat
            coord_ubs_lon,
            ivs,
            cnes,
            nome_fantasia, # coord_ubs_lon
            distancia               
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
        "Populacao_Atendida_ESF" => [r.populacao_atendida_total_eq_1 for r in population_results],
        "Populacao_Atendida_ESB" => [r.populacao_atendida_total_eq_2 for r in population_results],
        "Populacao_Atendida_ENASF" => [r.populacao_atendida_total_ENASF_2 for r in population_results],
        "UBS_Alocada" => [r.ubs_alocada for r in population_results],
        "Lat_Demanda" => [r.coord_demanda_lat for r in population_results],
        "Lon_Demanda" => [r.coord_demanda_lon for r in population_results],
        "Lat_UBS" => [r.coord_ubs_lat for r in population_results],
        "Lon_UBS" => [r.coord_ubs_lon for r in population_results], 
        "IVS" => [r.ivs for r in population_results],
        "Cnes_Destino" => [r.cnes for r in population_results],
        "Nome_Fantasia_Destino" => [r.nome_fantasia for r in population_results],
        "Distancia" => [r.distancia for r in population_results]
    )
    
    # Adicionar coluna de percentual de atendimento
    #df[!, "Percentual_Atendimento"] = [round(r.populacao_atendida / r.populacao_total * 100, digits=2) for r in population_results]
    
    # Salvar no Excel
    XLSX.writetable(filename, df)
    
    println("Tabela salva com sucesso!")
    println("Resumo dos resultados:")
    println("  - Total de pontos de demanda: ", nrow(df))
    println("  - População total: ", sum(df.Populacao_Total))
    #println("  - População atendida: ", round(sum(df.Populacao_Atendida), digits=0))
    #println("  - Percentual médio de atendimento: ", round(mean(df.Percentual_Atendimento), digits=2), "%")
    
    return df
end

"""
Extrai os resultados dos custos do modelo e retorna uma lista de CostResults
"""
function extract_cost_results(model)
    println("Extraindo resultados dos custos...")
    
    results = CostResults[]
    
    # Extrair valores das expressions do modelo
    custo_contratacao_equipes_esf = value(model[:custo_contratacao_equipes_esf])
    custo_realocaca_equipes_esf = value(model[:custo_realocaca_equipes_esf])
    custo_mensal_equipes_esf = value(model[:custo_mensal_equipes_esf])
    
    custo_contratacao_equipes_esb = value(model[:custo_contratacao_equipes_esb])
    custo_realocaca_equipes_esb = value(model[:custo_realocaca_equipes_esb])
    custo_mensal_equipes_esb = value(model[:custo_mensal_equipes_esb])
    
    custo_contratacao_equipes_enasf = value(model[:custo_contratacao_equipes_enasf])
    custo_realocaca_equipes_enasf = value(model[:custo_realocaca_equipes_enasf])
    custo_mensal_equipes_enasf = value(model[:custo_mensal_equipes_enasf])
    
    custo_fixo = value(model[:custo_fixo])
    custo_abertura = value(model[:custo_abertura])
    
    # Custos agregados (já definidos no modelo)
    custo_contratacao_total = value(model[:custo_contratacao])
    custo_realocacao_total = value(model[:custo_realocaca_equipes])
    custo_mensal_total = value(model[:custo_mensal_equipes])
    custo_total = value(model[:custo_total])
    
    # Custos por categoria de equipe
    custo_esf_total = custo_contratacao_equipes_esf + custo_realocaca_equipes_esf + custo_mensal_equipes_esf
    custo_esb_total = custo_contratacao_equipes_esb + custo_realocaca_equipes_esb + custo_mensal_equipes_esb
    custo_enasf_total = custo_contratacao_equipes_enasf + custo_realocaca_equipes_enasf + custo_mensal_equipes_enasf
    custo_infraestrutura_total = custo_fixo + custo_abertura
    
    # === CUSTOS DETALHADOS POR TIPO DE EQUIPE ===
    
    # Equipes ESF
    push!(results, CostResults("Contratação ESF", "ESF", custo_contratacao_equipes_esf,
                              round(100 * custo_contratacao_equipes_esf / custo_total, digits=2),
                              "Custo de contratação de novas equipes ESF"))
    
    push!(results, CostResults("Realocação ESF", "ESF", custo_realocaca_equipes_esf,
                              round(100 * custo_realocaca_equipes_esf / custo_total, digits=2),
                              "Custo de realocação de equipes ESF existentes"))
    
    push!(results, CostResults("Operação ESF", "ESF", custo_mensal_equipes_esf,
                              round(100 * custo_mensal_equipes_esf / custo_total, digits=2),
                              "Custo operacional mensal das equipes ESF"))
    
    # Equipes ESB
    push!(results, CostResults("Contratação ESB", "ESB", custo_contratacao_equipes_esb,
                              round(100 * custo_contratacao_equipes_esb / custo_total, digits=2),
                              "Custo de contratação de novas equipes ESB"))
    
    push!(results, CostResults("Realocação ESB", "ESB", custo_realocaca_equipes_esb,
                              round(100 * custo_realocaca_equipes_esb / custo_total, digits=2),
                              "Custo de realocação de equipes ESB existentes"))
    
    push!(results, CostResults("Operação ESB", "ESB", custo_mensal_equipes_esb,
                              round(100 * custo_mensal_equipes_esb / custo_total, digits=2),
                              "Custo operacional mensal das equipes ESB"))
    
    # Equipes ENASF
    push!(results, CostResults("Contratação ENASF", "ENASF", custo_contratacao_equipes_enasf,
                              round(100 * custo_contratacao_equipes_enasf / custo_total, digits=2),
                              "Custo de contratação de novas equipes ENASF"))
    
    push!(results, CostResults("Realocação ENASF", "ENASF", custo_realocaca_equipes_enasf,
                              round(100 * custo_realocaca_equipes_enasf / custo_total, digits=2),
                              "Custo de realocação de equipes ENASF existentes"))
    
    push!(results, CostResults("Operação ENASF", "ENASF", custo_mensal_equipes_enasf,
                              round(100 * custo_mensal_equipes_enasf / custo_total, digits=2),
                              "Custo operacional mensal das equipes ENASF"))
    
    # === CUSTOS DE INFRAESTRUTURA ===
    
    push!(results, CostResults("Custo Fixo UBS", "Infraestrutura", custo_fixo,
                              round(100 * custo_fixo / custo_total, digits=2),
                              "Custo fixo de manutenção das UBS"))
    
    push!(results, CostResults("Abertura UBS", "Infraestrutura", custo_abertura,
                              round(100 * custo_abertura / custo_total, digits=2),
                              "Custo de abertura de novas UBS"))
    
    # === TOTAIS POR CATEGORIA DE EQUIPE ===
    
    push!(results, CostResults("Total ESF", "Total por Equipe", custo_esf_total,
                              round(100 * custo_esf_total / custo_total, digits=2),
                              "Custo total das equipes ESF"))
    
    push!(results, CostResults("Total ESB", "Total por Equipe", custo_esb_total,
                              round(100 * custo_esb_total / custo_total, digits=2),
                              "Custo total das equipes ESB"))
    
    push!(results, CostResults("Total ENASF", "Total por Equipe", custo_enasf_total,
                              round(100 * custo_enasf_total / custo_total, digits=2),
                              "Custo total das equipes ENASF"))
    
    push!(results, CostResults("Total Infraestrutura", "Total por Categoria", custo_infraestrutura_total,
                              round(100 * custo_infraestrutura_total / custo_total, digits=2),
                              "Custo total de infraestrutura"))
    
    # === TOTAIS POR TIPO DE CUSTO ===
    
    push!(results, CostResults("Total Contratação", "Total por Tipo", custo_contratacao_total,
                              round(100 * custo_contratacao_total / custo_total, digits=2),
                              "Custo total de contratação de novas equipes"))
    
    push!(results, CostResults("Total Realocação", "Total por Tipo", custo_realocacao_total,
                              round(100 * custo_realocacao_total / custo_total, digits=2),
                              "Custo total de realocação de equipes"))
    
    push!(results, CostResults("Total Operação", "Total por Tipo", custo_mensal_total,
                              round(100 * custo_mensal_total / custo_total, digits=2),
                              "Custo total operacional mensal"))
    
    # === CUSTO TOTAL ===
    
    push!(results, CostResults("CUSTO TOTAL", "Total Geral", custo_total, 100.0, 
                              "Custo total do sistema de saúde"))
    
    println("Extraídos resultados para ", length(results), " tipos de custo")
    return results
end

"""
Extrai os resultados das variáveis eq_ESF_n1 e eq_ESB_n1 e retorna um DataFrame unificado com as colunas:
- tipo_equipe: 1 para ESF, 2 para ESB
- Indice_UBS: índice da UBS de destino (n1)
- Valor_Variavel: valor da variável (alocação da equipe na UBS)
- Origem_Equipe: índice da UBS de origem da equipe (posição no vetor de origem)
"""
function extract_team_flow_results(model::Model, indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::DataFrame
    println("Extraindo resultados do fluxo de equipes (ESF e ESB)...")

    # Verificações de existência das variáveis no modelo
    has_esf = haskey(model.obj_dict, :eq_ESF_n1)
    has_esb = haskey(model.obj_dict, :eq_ESB_n1)
    has_enasf = haskey(model.obj_dict, :eq_ENASF_n1)

    if !has_esf && !has_esb
        error("Variáveis eq_ESF_n1 e eq_ESB_n1 não encontradas no modelo!")
    end

    # Extrair valores das variáveis (se existirem)
    esf_vals = has_esf ? value.(model[:eq_ESF_n1]) : Dict{Tuple{Int,Int},Float64}()
    esb_vals = has_esb ? value.(model[:eq_ESB_n1]) : Dict{Tuple{Int,Int},Float64}()
    enasf_vals = has_enasf ? value.(model[:eq_ENASF_n1]) : Dict{Tuple{Int,Int},Float64}()

    # Vetores para construção do DataFrame
    tipos = Int[]
    ubs_indices = Int[]
    cnes_ubs_origem = Int[]
    valores = Float64[]
    origens = Int[]
    indice_eq = Int[]
    cnes_equipe = Int[]
    lat_und_origem = Float64[]
    long_und_origem = Float64[] 
    lat_destindo = Float64[]
    long_destino = Float64[]
    #mun_data.equipes_ESB_primario_v2.CO_EQUIPE[eq]
    cnes_UBS_destino = Int[]

    # ESF (tipo_equipe = 1)

    if has_esf
        for eq in indices.S_Equipes_ESF
            origem_eq = (eq <= length(indices.S_origem_equipes_ESF)) ? indices.S_origem_equipes_ESF[eq] : -1
            for n1 in indices.S_n1
                if esf_vals[eq, n1] !== nothing
                    v = esf_vals[eq, n1]
                    if v > 0
                    # Exportar todos os registros existentes (incluindo zeros) para transparência
                        push!(indice_eq, eq)
                        push!(cnes_equipe, mun_data.equipes_ESF_primario_v2.CO_EQUIPE[eq])
                        push!(tipos, 1)
                        push!(ubs_indices, n1) #destino!
                        push!(valores, v)
                        push!(origens, origem_eq)
                        push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
                        push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq] )
                        push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
                        if n1 > length(mun_data.unidades_n1.cnes)
                            new_n1 = n1 - length(mun_data.unidades_n1.cnes)
                            push!(cnes_UBS_destino, 0) #Equipe é candidata!
                            push!(lat_destindo, mun_data.coordenadas[new_n1][1])
                            push!(long_destino, mun_data.coordenadas[new_n1][2] )
                        else
                            push!(cnes_UBS_destino, mun_data.unidades_n1.cnes[n1])
                            push!(lat_destindo, mun_data.unidades_n1.latitude[n1] )
                            push!(long_destino, mun_data.unidades_n1.longitude[n1] )
                        
                            #localizacao da origem!
                        end    # Se nenhuma equipe tiver valor v > 0, salve as mesmas informações sem as informações da UBS de destino

                        
                    end
                end
            end

        if isempty(valores)
                push!(indice_eq, eq)
                push!(cnes_equipe, mun_data.equipes_ESF_primario_v2.CO_EQUIPE[eq])
                push!(tipos, 1)
                push!(ubs_indices, 0)
                push!(valores, 0.0)
                push!(origens, origem_eq)
                push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
                push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
                push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq])
                push!(cnes_UBS_destino, 0)
                push!(lat_destindo, 0)
                push!(long_destino, 0)
        end
        end
    end

    # ESB (tipo_equipe = 2)
    if has_esb
        for eq in indices.S_Equipes_ESB
            origem_eq = (eq <= length(indices.S_origem_equipes_ESB)) ? indices.S_origem_equipes_ESB[eq] : -1
            for n1 in indices.S_n1
                if esb_vals[eq, n1] !== nothing
                    v = esb_vals[eq, n1]
                    if v > 0
                        push!(indice_eq, eq)
                        push!(cnes_equipe, mun_data.equipes_ESB_primario_v2.CO_EQUIPE[eq])
                        push!(tipos, 2)
                        push!(ubs_indices, n1)
                        push!(valores, v)
                        push!(origens, origem_eq)
                        push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
                        push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq] )
                        push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
                        if n1 > length(mun_data.unidades_n1.cnes)
                            new_n1 = n1 - length(mun_data.unidades_n1.cnes)
                            push!(cnes_UBS_destino, 0) #Equipe é candidata!
                            push!(lat_destindo, mun_data.coordenadas[new_n1][1])
                            push!(long_destino, mun_data.coordenadas[new_n1][2] )
                        else
                            push!(cnes_UBS_destino, mun_data.unidades_n1.cnes[n1])
                            push!(lat_destindo, mun_data.unidades_n1.latitude[n1] )
                            push!(long_destino, mun_data.unidades_n1.longitude[n1] )
                        end
                    end
                end
            end
        if isempty(valores)
            push!(indice_eq, eq)
            push!(cnes_equipe, mun_data.equipes_ESB_primario_v2.CO_EQUIPE[eq])
            push!(tipos, 2)
            push!(ubs_indices, 0)
            push!(valores, 0.0)
            push!(origens, origem_eq)
            push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
            push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
            push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq])
            push!(cnes_UBS_destino, 0)
            push!(lat_destindo, 0)
            push!(long_destino, 0)
        end
        end
    end

        # ESB (tipo_equipe = 2)
    if has_enasf
        for eq in indices.S_Equipes_ENASF
            origem_eq = (eq <= length(indices.S_origem_equipes_ENASF)) ? indices.S_origem_equipes_ENASF[eq] : -1
            for n1 in indices.S_n1
                if enasf_vals[eq, n1] !== nothing
                    v = enasf_vals[eq, n1]
                    if v > 0
                        push!(indice_eq, eq)
                        push!(cnes_equipe, mun_data.equipes_ENASF_primario_v2.CO_EQUIPE[eq])
                        push!(tipos, 3)
                        push!(ubs_indices, n1)
                        push!(valores, v)
                        push!(origens, origem_eq)
                        push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
                        push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq] )
                        push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
                        if n1 > length(mun_data.unidades_n1.cnes)
                            new_n1 = n1 - length(mun_data.unidades_n1.cnes)
                            push!(cnes_UBS_destino, 0) #Equipe é candidata!
                            push!(lat_destindo, mun_data.coordenadas[new_n1][1])
                            push!(long_destino, mun_data.coordenadas[new_n1][2] )
                        else
                            push!(cnes_UBS_destino, mun_data.unidades_n1.cnes[n1])
                            push!(lat_destindo, mun_data.unidades_n1.latitude[n1] )
                            push!(long_destino, mun_data.unidades_n1.longitude[n1] )
                        end
                    end
                end
            end
        if isempty(valores)
            push!(indice_eq, eq)
            push!(cnes_equipe, mun_data.equipes_ENASF_primario_v2.CO_EQUIPE[eq])
            push!(tipos, 3)
            push!(ubs_indices, 0)
            push!(valores, 0.0)
            push!(origens, origem_eq)
            push!(cnes_ubs_origem, mun_data.unidades_n1.cnes[origem_eq])
            push!(lat_und_origem, mun_data.unidades_n1.latitude[origem_eq])
            push!(long_und_origem, mun_data.unidades_n1.longitude[origem_eq])
            push!(cnes_UBS_destino, 0)
            push!(lat_destindo, 0)
            push!(long_destino, 0)
        end
        end
    end
    

    enasf_vals






    df = DataFrame(
        "tipo_equipe" => tipos,
        "Indice_UBS" => ubs_indices,
        "Valor_Variavel" => valores,
        "Origem_Equipe" => origens,
        "Indice_equipe" => indice_eq,
        "cnes_eq" => cnes_equipe,
        "cnes_ubs_origem" => cnes_ubs_origem, 
        "cnes_UBS_destino" => cnes_UBS_destino, 
        "lat_origem" => lat_und_origem,
        "long_origem" => long_und_origem,
        "lat_destino" => lat_destindo,
        "long_destino" => long_destino
    )

    println("Linhas exportadas (fluxo de equipes): ", nrow(df))
    return df
end


function add_flow_patientes_to_excel(df::DataFrame, filename::String)
    XLSX.openxlsx(filename, mode="rw") do xf
        sheet = XLSX.addsheet!(xf, "Fluxo_Pacientes")

        # Cabeçalhos conforme DataFrame
        headers = names(df)
        for (j, h) in enumerate(headers)
            col = Char('A' + j - 1)
            sheet["$(col)1"] = String(h)
        end

        # Escrever dados
        for (i, row) in enumerate(eachrow(df))
            for (j, h) in enumerate(headers)
                col = Char('A' + j - 1)
                sheet["$(col)$(i+1)"] = row[h]
            end
        end
    end

    println("Aba 'Fluxo_Equipes' adicionada com sucesso!")
    println("Linhas: ", nrow(df), " | Colunas: ", ncol(df))
    return df
end

"""
Extrai as alocações ESF→Emulti do modelo `model_emulti` (variável `aloc_ESF`) e retorna um DataFrame.

Colunas:
- Indice_ESF: índice da equipe ESF (i)
- Indice_Emulti: índice da equipe Emulti (j)
- Valor: valor binário da variável aloc_ESF[i,j]
- cnes_eq_esf: código da equipe ESF (quando disponível em `mun_data`)
- ubs_origem_esf: CNES da UBS de origem da ESF (quando disponível via `indices.S_origem_equipes_ESF`)
- lat_origem_esf, long_origem_esf: coordenadas da UBS de origem da ESF (quando disponíveis)
"""
function extract_aloc_esf_emulti(model_emulti::Model, indices_model_emulti::Indices_modelo_alocacao_ESF_Emulti, indices::ModelIndices, mun_data::MunicipalityData)::DataFrame
    if !haskey(model_emulti.obj_dict, :aloc_ESF)
        error("Variável aloc_ESF não encontrada em model_emulti")
    end

    aloc_vals = value.(model_emulti[:aloc_ESF])


    #indices_model_emulti.UBS_ESF_alocada_real
    indice_maximo_equipes_reais_ESF = length(indices_model_emulti.ESF_Reais_abertas)
    indice_maximo_equipes_reais_Emulti = length(indices_model_emulti.UBS_EMulti_alocada_real)
    idx_esf = Int[]
    idx_emulti = Int[]
    valores = Float64[]
    cnes_eq_esf = Int[]
    cnes_eq_emulti = Int[]
    ubs_origem_esf = Int[]
    ubs_origem_emulti = Int[]
    lat_origem_esf = Float64[]
    long_origem_esf = Float64[]
    lat_emulti = Float64[]
    long_emulti = Float64[]

    #for key in keys(aloc_vals)
    for i in axes(aloc_vals, 1), j in axes(aloc_vals, 2)
        #i, j = key
        v = aloc_vals[i,j]
        if v > 0
        #Indices das ESF
            if i <= indice_maximo_equipes_reais_ESF
                idx_equipe = indices_model_emulti.ESF_Reais_abertas[i]
                push!(idx_esf, idx_equipe)
                push!(cnes_eq_esf, mun_data.equipes_ESF_primario_v2.CO_EQUIPE[idx_equipe])
                #push!(idx_emulti, j)
                push!(valores, v)

                #Qual UBS a equipe está alocada ?
                #Equipes reais
                ubs_alocada = indices_model_emulti.UBS_ESF_alocada_real[i] #QUal UBS a equipe i esta alocada ?
                mun_data.unidades_n1.cnes[27]
                #Essa ubs é real ou é criada ?
                if ubs_alocada <= length(mun_data.unidades_n1.cnes)
                    #Real!
                    push!(ubs_origem_esf, ubs_alocada)
                    push!(lat_origem_esf, mun_data.unidades_n1.latitude[ubs_alocada])
                    push!(long_origem_esf, mun_data.unidades_n1.longitude[ubs_alocada])
                else
                    #UBS foi criada e é um ponto de demanda!
                    push!(ubs_origem_esf, ubs_alocada)
                    #qual é o ponto de demanda ?
                    ponto_demanda_origem = ubs_alocada - nrow(mun_data.unidades_n1) 
                    push!(lat_origem_esf, mun_data.coordenadas[ponto_demanda_origem][1])
                    push!(long_origem_esf,  mun_data.coordenadas[ponto_demanda_origem][2])
                end
            else
                #Equipes criadas!
                pos_equipe = i - indice_maximo_equipes_reais_ESF
                idx_equipe = indices_model_emulti.ESF_criadas[pos_equipe]
                push!(idx_esf, idx_equipe)
                push!(cnes_eq_esf, idx_equipe)
                #push!(idx_emulti, j)
                push!(valores, v)
                
                ubs_alocada = indices_model_emulti.UBS_ESF_alocada_candidata[pos_equipe] #qual UBS ela esta ?
                #Essa ubs é real ou é criada ?
                if ubs_alocada <= length(mun_data.unidades_n1.cnes)
                    #Real!
                    push!(ubs_origem_esf, ubs_alocada)
                    push!(lat_origem_esf, mun_data.unidades_n1.latitude[ubs_alocada])
                    push!(long_origem_esf, mun_data.unidades_n1.longitude[ubs_alocada])
                else
                    #UBS foi criada e é um ponto de demanda!
                    push!(ubs_origem_esf, ubs_alocada)
                    #qual é o ponto de demanda ?
                    ponto_demanda_origem = ubs_alocada - nrow(mun_data.unidades_n1) 
                    push!(lat_origem_esf, mun_data.coordenadas[ponto_demanda_origem][1])
                    push!(long_origem_esf,  mun_data.coordenadas[ponto_demanda_origem][2])
                end
            end
        #Indices das Emulti
            if j <= indice_maximo_equipes_reais_Emulti
                idx_equipe = indices_model_emulti.EMulti_Reais_abertas[j]
                push!(idx_emulti, idx_equipe)
                push!(cnes_eq_emulti, mun_data.equipes_ENASF_primario_v2.CO_EQUIPE[idx_equipe])
                ubs_alocada = indices_model_emulti.UBS_EMulti_alocada_real[j]
                if ubs_alocada <= length(mun_data.unidades_n1.cnes)
                    #Real!
                    push!(ubs_origem_emulti, ubs_alocada)
                    push!(lat_emulti, mun_data.unidades_n1.latitude[ubs_alocada])
                    push!(long_emulti, mun_data.unidades_n1.longitude[ubs_alocada])
                else
                    #UBS foi criada e é um ponto de demanda!
                    push!(ubs_origem_esf, ubs_alocada)
                    #qual é o ponto de demanda ?
                    ponto_demanda_origem = ubs_alocada - nrow(mun_data.unidades_n1) 
                    push!(lat_emulti, mun_data.coordenadas[ponto_demanda_origem][1])
                    push!(long_emulti,  mun_data.coordenadas[ponto_demanda_origem][2])
                end
            else
                #Equipes criadas!
                pos_equipe = j - indice_maximo_equipes_reais_Emulti
                idx_equipe = indices_model_emulti.Emulti_criadas[pos_equipe]
                push!(idx_emulti, idx_equipe)
                push!(cnes_eq_emulti, idx_equipe)
                #push!(idx_emulti, j)
                push!(valores, v)
                
                ubs_alocada = indices_model_emulti.UBS_Emulti_criadas[pos_equipe] #qual UBS ela esta ?
                #Essa ubs é real ou é criada ?
                if ubs_alocada <= length(mun_data.unidades_n1.cnes)
                    #Real!
                    push!(ubs_origem_emulti, ubs_alocada)
                    push!(lat_emulti, mun_data.unidades_n1.latitude[ubs_alocada])
                    push!(long_emulti, mun_data.unidades_n1.longitude[ubs_alocada])
                else
                    #UBS foi criada e é um ponto de demanda!
                    push!(ubs_origem_emulti, ubs_alocada)
                    #qual é o ponto de demanda ?
                    ponto_demanda_origem = ubs_alocada - nrow(mun_data.unidades_n1) 
                    push!(lat_emulti, mun_data.coordenadas[ponto_demanda_origem][1])
                    push!(long_emulti,  mun_data.coordenadas[ponto_demanda_origem][2])
                end

            end
        end
    end

    return DataFrame(
        "Indice_ESF" => idx_esf,
        "Indice_Emulti" => idx_emulti,
        "Valor" => valores,
        "cnes_eq_esf" => cnes_eq_esf,
        "ubs_origem_esf" => ubs_origem_esf,
        "lat_origem_esf" => lat_origem_esf,
        "long_origem_esf" => long_origem_esf,
        "cnes_eq_emulti" => cnes_eq_emulti,
        "lat_emulti" => lat_emulti,
        "long_emulti" => long_emulti
    )
end

function add_aloc_esf_emulti_to_excel(df::DataFrame, filename::String)
    XLSX.openxlsx(filename, mode="rw") do xf
        sheet = XLSX.addsheet!(xf, "Aloc_ESF_Emulti")
        headers = names(df)
        for (j, h) in enumerate(headers)
            col = Char('A' + j - 1)
            sheet["$(col)1"] = String(h)
        end
        for (i, row) in enumerate(eachrow(df))
            for (j, h) in enumerate(headers)
                col = Char('A' + j - 1)
                sheet["$(col)$(i+1)"] = row[h]
            end
        end
    end
    println("Aba 'Aloc_ESF_Emulti' adicionada com sucesso!")
    return df
end

"""
Extrai os resultados das variáveis eq_ESF_criadas e eq_ESB_criadas e retorna um DataFrame com as colunas:
- Unidade_UBS
- eq_ESB_criadas
- eq_ESF_criadas
"""
function extract_created_teams_df(model::Model, indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::DataFrame
    println("Extraindo resultados de equipes criadas (ESF e ESB)...")

    has_esf_criadas = haskey(model.obj_dict, :eq_ESF_criadas)
    has_esb_criadas = haskey(model.obj_dict, :eq_ESB_criadas)
    has_enasf_criadas = haskey(model.obj_dict, :eq_enasf_criadas)
    has_coebertura_enasf = haskey(model.obj_dict, :cobertura_ENASF)

    if !has_esf_criadas && !has_esb_criadas
        error("Variáveis eq_ESF_criadas e eq_ESB_criadas não encontradas no modelo!")
    end

    esf_criadas = has_esf_criadas ? value.(model[:eq_ESF_criadas]) : Dict{Int,Float64}()
    esb_criadas = has_esb_criadas ? value.(model[:eq_ESB_criadas]) : Dict{Int,Float64}()
    enasf_criadas = has_enasf_criadas ? value.(model[:eq_enasf_criadas]) : Dict{Int,Float64}()
    cobertura_enasf = has_enasf_criadas ? value.(model[:cobertura_ENASF]) : Dict{Int,Float64}()

    ubs = Int[]
    v_esb = Float64[]
    v_esf = Float64[]
    v_enasf = Float64[]
    v_cobertura_enasf = []

    for n1 in indices.S_n1
        push!(ubs, n1)
        push!(v_esb, value.(model[:eq_ESB_criadas])[n1])
        push!(v_esf, value.(model[:eq_ESF_criadas])[n1])
        push!(v_enasf, value.(model[:eq_enasf_criadas])[n1])
        push!(v_cobertura_enasf, value.(model[:cobertura_ENASF])[n1])
    end

    df = DataFrame(
        "Unidade_UBS" => ubs,
        "eq_ESB_criadas" => v_esb,
        "eq_ESF_criadas" => v_esf,
        "eq_ENASF_criadas" => v_enasf,
        "tem_cobertura_enasf" => v_cobertura_enasf
    )

    println("Linhas exportadas (equipes criadas): ", nrow(df))
    return df
end

"""
Gera uma planilha Excel com o DataFrame do fluxo de equipes (ESF e ESB) já no novo formato
"""
function export_team_flow_results_to_excel(df_team_flow::DataFrame, 
                                         filename::String="resultados_fluxo_equipes.xlsx")
    println("Gerando tabela Excel do fluxo de equipes: ", filename)

    # Salvar no Excel diretamente a partir do DataFrame fornecido
    XLSX.writetable(filename, df_team_flow)

    println("Tabela de fluxo de equipes salva com sucesso!")
    println("Linhas: ", nrow(df_team_flow), " | Colunas: ", ncol(df_team_flow))
    return df_team_flow
end

"""
Adiciona o DataFrame do fluxo de equipes (novo formato) a uma aba existente do Excel
"""
function add_team_flow_to_excel(df::DataFrame, filename::String)
    println("Adicionando resultados do fluxo de equipes ao arquivo: ", filename)

    # Abrir arquivo Excel existente e adicionar nova aba
    XLSX.openxlsx(filename, mode="rw") do xf
        sheet = XLSX.addsheet!(xf, "Fluxo_Equipes")

        # Cabeçalhos conforme DataFrame
        headers = names(df)
        for (j, h) in enumerate(headers)
            col = Char('A' + j - 1)
            sheet["$(col)1"] = String(h)
        end

        # Escrever dados
        for (i, row) in enumerate(eachrow(df))
            for (j, h) in enumerate(headers)
                col = Char('A' + j - 1)
                sheet["$(col)$(i+1)"] = row[h]
            end
        end
    end

    println("Aba 'Fluxo_Equipes' adicionada com sucesso!")
    println("Linhas: ", nrow(df), " | Colunas: ", ncol(df))
    return df
end

"""
Adiciona o DataFrame de equipes criadas (ESF/ESB) a uma aba existente do Excel
"""
function add_created_teams_to_excel(df_created::DataFrame, filename::String)
    println("Adicionando resultados de equipes criadas ao arquivo: ", filename)

    XLSX.openxlsx(filename, mode="rw") do xf
        sheet = XLSX.addsheet!(xf, "Equipes_Criadas")

        headers = names(df_created)
        for (j, h) in enumerate(headers)
            col = Char('A' + j - 1)
            sheet["$(col)1"] = String(h)
        end

        for (i, row) in enumerate(eachrow(df_created))
            for (j, h) in enumerate(headers)
                col = Char('A' + j - 1)
                sheet["$(col)$(i+1)"] = row[h]
            end
        end
    end

    println("Aba 'Equipes_Criadas' adicionada com sucesso!")
    return df_created
end


function extract_flow_patients(model::Model, indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::DataFrame
    
    #X_n2
    #X_n3
    pop_fluxo_sec = value.(model[:X_n2])
    pop_fluxo_terc = value.(model[:X_n3])
    nivel = Int[]
    indice_origem = Int[]
    indice_destino = Int[]
    cnes_origem = Int[]
    cnes_destino = Int[]
    fluxo_pacientes = Float64[]
    lat_origem = Float64[]
    long_origem = Float64[]
    lat_destino = Float64[]
    long_destino = Float64[]
    n2_mais_proximo = Dict{Int, Int}()

    Matriz_Dist_n1 = parameters.S_Matriz_Dist.Matriz_Dist_n1
    Matriz_Dist_n2 = parameters.S_Matriz_Dist.Matriz_Dist_n2
    Matriz_Dist_n3 = parameters.S_Matriz_Dist.Matriz_Dist_n3
    
    for n1 in indices.S_n1
        if !isempty(parameters.S_domains.dominio_n2[n1])
            n2_mais_proximo[n1] = argmin(n2 -> Matriz_Dist_n2[n1, n2], parameters.S_domains.dominio_n2[n1])
        end
    end

    n3_mais_proximo = Dict{Int, Int}()
    for n2 in indices.S_n2
        if !isempty(parameters.S_domains.dominio_n3[n2])
            n3_mais_proximo[n2] = argmin(n3 -> Matriz_Dist_n3[n2, n3], parameters.S_domains.dominio_n3[n2])
        end
    end


    for n1 in indices.S_n1, n2 in n2_mais_proximo[n1]
        vl_fl = pop_fluxo_sec[n1, n2]
        if vl_fl > 0
            push!(nivel, 2)
            push!(indice_origem, n1)
            push!(indice_destino, n2)
            push!(cnes_destino, mun_data.unidades_n2.cnes[n2])
            #Estou considerando somente a possibilidade da origem como candidato porque nivel secundario e terciario sao somente existentes.
            push!(lat_destino, mun_data.unidades_n2.latitude[n2])
            push!(long_destino, mun_data.unidades_n2.longitude[n2])
            push!(fluxo_pacientes, vl_fl)
            if n1 <= length(mun_data.unidades_n1.cnes) #Origem Real
                push!(cnes_origem, mun_data.unidades_n1.cnes[n1])
                push!(lat_origem,  mun_data.unidades_n1.latitude[n1])
                push!(long_origem, mun_data.unidades_n1.longitude[n1])
            else
                push!(cnes_origem, n1) #Origem Destino
                push!(lat_origem,  mun_data.coordenadas[n1][1])
                push!(long_origem, mun_data.coordenadas[n1][2])
            end
        end
    end


    for n2 in indices.S_n2, n3 in n3_mais_proximo[n2]
        vl_fl = pop_fluxo_terc[n2, n3]
        if vl_fl > 0
            push!(nivel, 3)
            push!(indice_origem, n2)
            push!(indice_destino, n3)
            push!(cnes_destino, mun_data.unidades_n3.cnes[n3])
            push!(lat_destino, mun_data.unidades_n3.latitude[n3])
            push!(long_destino, mun_data.unidades_n3.longitude[n3])
            push!(fluxo_pacientes, vl_fl)
            push!(cnes_origem, mun_data.unidades_n2.cnes[n2])
            push!(lat_origem,  mun_data.unidades_n2.latitude[n2])
            push!(long_origem, mun_data.unidades_n2.longitude[n2])

        end
    end


    df = DataFrame(
        "Nivel_Destino" => nivel,
        "Indice_Origem" => indice_origem,
        "Indice_Destino" => indice_destino,
        "Cnes_Origem" => cnes_origem,
        "Cnes_Destino" => cnes_destino,
        "Fluxo_pacientes" => fluxo_pacientes,
        "lat_origem" => lat_origem,
        "long_origem" => long_origem,
        "lat_destino" => lat_destino,
        "long_destino" => long_destino
    )
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


function create_optimization_model_maximal_coverage_INICIAL(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

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



function create_optimization_model_maximal_coverage_fluxo_equipes(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

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

    Orcamento_Maximo = parameters.orcamento_maximo
    ponderador_Vulnerabilidade = parameters.ponderador_Vulnerabilidade
    S_IVS = ponderador_Vulnerabilidade .* parameters.IVS

    S_Equipes_ESF =  indices.S_Equipes_ESF
    S_Equipes_ESB =  indices.S_Equipes_ESB
    S_Equipes_ENASF = S_Equipes_ENASF_Reais = indices.S_Equipes_ENASF
    
    S_origem_equipes_ESB = indices.S_origem_equipes_ESB
    S_origem_equipes_ESF = indices.S_origem_equipes_ESF
    S_origem_equipes_ENASF = indices.S_origem_equipes_ENASF
    mt_emulti = parameters.S_Matriz_Dist.Matriz_Dist_Emulti
    dominio_UBS_Emulti = Dict(ubs_orig => [ubs_dest for ubs_dest in S_n1 if mt_emulti[ubs_orig, ubs_dest] <= 5] for ubs_orig in S_n1)

    n2_mais_proximo = Dict{Int, Int}()
    for n1 in S_n1
        if !isempty(dominio_atr_n2[n1])
            n2_mais_proximo[n1] = argmin(n2 -> Matriz_Dist_n2[n1, n2], dominio_atr_n2[n1])
        end
    end

    n3_mais_proximo = Dict{Int, Int}()
    for n2 in S_n2
        if !isempty(dominio_atr_n3[n2])
            n3_mais_proximo[n2] = argmin(n3 -> Matriz_Dist_n3[n2, n3], dominio_atr_n3[n2])
        end
    end



    cap_equipes_n1 = 3000

    model = Model(HiGHS.Optimizer)

    #Variaveis
    S_equipes = [1,2]
    #atribuicao primária
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin) #Abertura unidades primárias
    #Tipo_equipe (ESF OU ESB), Indice da equipe, destino!
    #TODO - v0 so com ESF!!

    fluxo_eq_ESF_n1 = @variable(model, eq_ESF_n1[eq in S_Equipes_ESF, n1 in S_n1], Bin) #Possibilidade de dividir a equipe ?
    fluxo_eq_ESB_n1 = @variable(model, eq_ESB_n1[eq in S_Equipes_ESB, n1 in S_n1], Bin) 
    eqs_ESF_criadas_n1 = @variable(model, eq_ESF_criadas[n1 in S_n1] >= 0)
    eqs_ESB_criadas_n1 = @variable(model, eq_ESB_criadas[n1 in S_n1] >= 0)
    var_pop_atendida = @variable(model, pop_atendida[d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]] >= 0) #Inserir aqui as demografias das populacoes!
    
    #inicialmente vou somente encaminhar demanda para niveis superiore
    #Fluxo n2
    fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in n2_mais_proximo[n1]] >= 0)
    var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
    #Fluxo n3
    fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in n3_mais_proximo[n2]] >= 0)
    var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)

    # ============================================================================================================
    # RESTRICOES DE TERRITORIZALICAO DAS UBS!
    # ============================================================================================================
    #Todas as unidades devem ser alocadas numa UBS de referencia
    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) <= 1)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] *  S_Valor_Demanda[d])
    #@constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d])
        #Abertura de unidades novas:
    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], 
        Aloc_[d, s] <= var_abr_n1[s] )

    @constraint(model, [n1 in S_instalacoes_reais_n1], Abr_n1[n1] == 1)


    
    # ============================================================================================================
    # Restricao EXTRA PARA TESTE DE MANTER UNIDADES ABERTAS!!!!
    # ============================================================================================================

    #Unidades reais precisam se manter funcionando, logo tem que ter pelo menos uma equipe lá atuando!
    @constraint(model, [n1 in S_instalacoes_reais_n1], sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) + eq_ESF_criadas[n1] >= 1)


    # ============================================================================================================
    # TUDO DE ENASF!!!
    # ============================================================================================================
     
    @variable(model, cobertura_ENASF[n1 in S_n1], Bin)
    @variable(model, eq_ENASF_n1[eq in S_Equipes_ENASF, n1 in S_n1] >= 0)
    @variable(model, eq_enasf_criadas[n1 in S_n1] >= 0)
    @variable(model, pop_coberta_ENASF[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]] >= 0)

    # UBS tem ENASF se recebe pelo menos uma equipe

    @constraint(model, [n1 in S_n1],
        cobertura_ENASF[n1] <= 
        sum(sum(eq_ENASF_n1[eq, j] for eq in S_Equipes_ENASF) + eq_enasf_criadas[j] 
            for j in dominio_UBS_Emulti[n1]))


    #Uma ENASF por Unidade
    @constraint(model, [n1 in S_n1],  sum(eq_ENASF_n1[eq, n1]  for eq in S_Equipes_ENASF)
    + eq_enasf_criadas[n1] <= 1)
    



    #Somente unidades abertas podem ser cobertas e receber ENASF
    @constraint(model, [n1 in S_n1], eq_enasf_criadas[n1] <= Abr_n1[n1])
    @constraint(model, [eq in S_Equipes_ENASF, n1 in S_n1], eq_ENASF_n1[eq, n1] <= Abr_n1[n1])

    @constraint(model, [eq in S_Equipes_ENASF], sum(eq_ENASF_n1[eq, n1] for n1 in S_n1) <= 1)
    

    M = maximum(S_Valor_Demanda)  # Big-M conservador

    # Restrições de linearização para cada setor/equipe/UBS
    @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
        pop_coberta_ENASF[d, n1] <= M * cobertura_ENASF[n1])

    @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
        pop_coberta_ENASF[d, n1] <= pop_atendida[d, 1, n1])

    @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
        pop_coberta_ENASF[d, n1] >= pop_atendida[d, 1, n1] - M * (1 - cobertura_ENASF[n1]))



    #AMANHA = Restricao de capacidade das ENASFs

    @constraint(model,
    (sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF, n1 in S_n1) + sum(eq_ESF_criadas[n1] for n1 in S_n1)) <= 
    9 * (sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF, n1 in S_n1) + sum(eq_enasf_criadas[n1] for n1 in S_n1)))
    

     # ============================================================================================================
    # SUGESTAO GROK PARA INFEASIBILITY
    # ============================================================================================================
    #@constraint(model, territorialization[d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) <= 1)
    # ============================================================================================================
    # ALOCACAO ESF E ESB
    # ============================================================================================================
    #Uma equipe so pode ser alocada em no maximo uma unidade!
    @constraint(model, [eq in S_Equipes_ESF], sum(eq_ESF_n1[eq, n1] for n1 in S_n1) <= 1)
    @constraint(model, [eq in S_Equipes_ESB], sum(eq_ESB_n1[eq, n1] for n1 in S_n1) <= 1)
 
    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 1, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= (sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) + eq_ESF_criadas[n1]) * 3000)


    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 2, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= (sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) + eq_ESB_criadas[n1]) * 3000)


    @constraint(model, [n1 in S_n1], sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF) + eq_ESF_criadas[n1] <= 4)


    @constraint(model, [n1 in S_n1], 
    sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) + eq_ESB_criadas[n1]  
        == sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) + eq_ESF_criadas[n1])



    #Equipes so podem ser alocadas em unidades abertas!
    @constraint(model, [eq in S_Equipes_ESF, n1 in S_n1], eq_ESF_n1[eq, n1] <= Abr_n1[n1])
    @constraint(model, [eq in S_Equipes_ESB, n1 in S_n1], eq_ESB_n1[eq, n1] <= Abr_n1[n1])
    #tambem preciso remover diminuir as equipes! - Posso assumir que se a equipe tiver custo negativo ela foi removida do sistema ?

    
    # ============================================================================================================
    # Restricao de Orcamento
    # ============================================================================================================
    @expression(model, custo_contratacao_equipes_esf, sum(eq_ESF_criadas[n1] for n1 in S_n1) * 50000)
    @expression(model, custo_realocaca_equipes_esf, sum((Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * eq_ESF_n1[eq, n1] / 9) * 6 for eq in S_Equipes_ESF, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esf, (sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF, n1 in S_n1) + sum(eq_ESF_criadas[n1] for n1 in S_n1))  * 50000)
    
    
    @expression(model, custo_contratacao_equipes_esb, sum(eq_ESB_criadas[n1] for n1 in S_n1) * 22000)
    @expression(model, custo_realocaca_equipes_esb, sum((Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * eq_ESB_n1[eq, n1] / 9) * 6  for eq in S_Equipes_ESB, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esb, (sum(eq_ESB_n1[eq, n1]  for eq in S_Equipes_ESB, n1 in S_n1) + sum(eq_ESB_criadas[n1] for n1 in S_n1)) * 22000)


    @expression(model, custo_contratacao_equipes_enasf, sum(eq_enasf_criadas[n1] for  n1 in S_n1) * 92000)
    @expression(model, custo_realocaca_equipes_enasf, sum((Matriz_Dist_n1[S_origem_equipes_ENASF[eq], n1] * eq_ENASF_n1[eq, n1] / 9) * 6  for eq in S_Equipes_ENASF_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_enasf, (sum(eq_ENASF_n1[eq, n1]  for eq in S_Equipes_ENASF, n1 in S_n1) + sum(eq_enasf_criadas[n1] for  n1 in S_n1)) * 92000)



    @expression(model, custo_fixo, sum(Abr_n1[n1] * 1500 for n1 in S_n1))
    @expression(model, custo_abertura, sum(Abr_n1[n1] * 10000 for n1 in S_locais_candidatos_n1))
    

    @expression(model, custo_contratacao, custo_contratacao_equipes_esf + custo_contratacao_equipes_esb + custo_contratacao_equipes_enasf)
    @expression(model, custo_realocaca_equipes, custo_realocaca_equipes_esf + custo_realocaca_equipes_esb + custo_mensal_equipes_enasf)
    @expression(model, custo_mensal_equipes, custo_mensal_equipes_esf + custo_mensal_equipes_esb + custo_mensal_equipes_enasf)


    @expression(model, custo_total, 
    custo_contratacao
    + custo_realocaca_equipes 
    + custo_mensal_equipes
    + custo_fixo
    + custo_abertura
   )

    @constraint(model, custo_total <= Orcamento_Maximo)

    # ============================================================================================================
    # Multi-Fluxo
    # ============================================================================================================

    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
    sum(X_n2[n1, n2] for n2 in n2_mais_proximo[n1]) == percent_n1_n2 * sum(pop_atendida[d, 1, n1] 
            for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))
    

    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
        sum(X_n3[n2, n3] for n3 in n3_mais_proximo[n2]) == 
        percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in n2_mais_proximo[n1]))
            


    #Funcao Objetivo:
    @objective(model, Max, sum(pop_atendida[d, eq, un] * S_IVS[d] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d]) 
    + sum(pop_coberta_ENASF[d, n1] * S_IVS[d] for d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]))
    #+ sum(var_equidade[eq] * vls_eq[eq] for eq in S_equipes)

    

    return model


    #set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-4)
    #set_optimizer_attribute(model, "dual_feasibility_tolerance", 1e-4)
    #set_optimizer_attribute(model, "time_limit", 300.0)
    #set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    # ... (your model definition)

    #optimize!(model)

    # ============================================================================================================
    # Solve
    # ============================================================================================================


    

    # ============================================================================================================
    # Pos-OTM
    # ============================================================================================================
    run_local = false
    if termination_status(model) == MOI.OPTIMAL && run_local
        println("=== Solução Ótima Encontrada ===")
        println("Valor do Objetivo: ", objective_value(model))
        


        #pop_atendida_ENSF = value.(model[:pop_coberta_ENASF])
        total_eq = 0.0
        for d in indices.S_Pontos_Demanda, n1 in indices.S_n1
            if n1 in parameters.S_domains.dominio_n1[d]
                total_eq += value(pop_coberta_ENASF[d,n1])
            end
        end
          println("Pop coberta por enasf: ", total_eq)
        

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
  

        # 1. UBS Abertas (Abr_n1)
        println("\n=== UBS Abertas ===")
        for n1 in S_n1
            if value(Abr_n1[n1]) > 0.5  # Binário, tolerância para 1
                println("UBS $n1: Aberta")
            else
                println("UBS $n1: Fechada")
            end
        end
    
        # 2. Alocação de Pontos de Demanda
        println("\n=== Alocação de Demanda para UBS ===")
        for d in S_Pontos_Demanda
            alocado = false
            for n1 in dominio_atr_n1[d]
                if value(Aloc_[d, n1]) > 0.5
                    println("Ponto $d alocado para UBS $n1")
                    alocado = true
                end
            end
            if !alocado
                println("Ponto $d NÃO alocado")
            end
        end
        

        enasf_alocadas = 0.0
        for eq in S_Equipes_ENASF, n1 in S_n1
            if value(eq_ENASF_n1[eq, n1]) > 0
                println("Equipe $eq alocado na UBS $n1 com valor de $(value(eq_ENASF_n1[eq, n1]))")
            end
        end


        
        
        for eq in S_Equipes_ESF, n1 in S_n1
            if value(eq_ESF_n1[eq, n1]) > 0
                println("Equipe $eq alocado na UBS $n1 com valor de $(value(eq_ESF_n1[eq, n1]))")
            end
        end


        # Soma total da variável eq_ESF_criadas[n1] para todas as UBS
        total_esf_criadas = sum(value(eq_ESF_criadas[n1]) for n1 in S_n1)
        println("\nTotal de ESF criadas: ", total_esf_criadas)

        total_esb_criadas = sum(value(eq_ESB_criadas[n1]) for n1 in S_n1)
        println("\nTotal de ESB criadas: ", total_esb_criadas)

        total_enasf_criadas = sum(value(eq_enasf_criadas[n1]) for n1 in S_n1)
        println("\nTotal de enasf criadas: ", total_enasf_criadas)

        # 3. Equipes Alocadas e Criadas
        println("\n=== Equipes Alocadas e Criadas por UBS ===")
        for n1 in S_n1
            println("\nUBS $n1:")
            # ESF
            esf_alocadas = 0.0
            for eq in S_Equipes_ESF
                if value(eq_ESF_n1[eq, n1]) > 0
                    esf_alocadas += value(eq_ESF_n1[eq, n1]) 
                end
            end
            #esf_alocadas = sum(value(eq_ESF_n1[eq, n1]) for eq in S_Equipes_ESF if value(eq_ESF_n1[eq, n1]) > 0.5)
            esf_criadas = round(value(eq_ESF_criadas[n1]), digits=2)
            println("  ESF: $esf_alocadas alocadas, $esf_criadas criadas")
            # ESB

            esb_alocadas = 0.0
            for eq in S_Equipes_ESB
                if value(eq_ESB_n1[eq, n1]) > 0
                    esb_alocadas += value(eq_ESB_n1[eq, n1]) 
                end
            end
            #esb_alocadas = sum(value(eq_ESB_n1[eq, n1]) for eq in S_Equipes_ESB if value(eq_ESB_n1[eq, n1]) > 0.5)
            esb_criadas = round(value(eq_ESB_criadas[n1]), digits=2)
            println("  ESB: $esb_alocadas alocadas, $esb_criadas criadas")
            # ENASF
            #enasf_alocadas = sum(value(eq_ENASF_n1[eq, n1]) for eq in S_Equipes_ENASF if value(eq_ENASF_n1[eq, n1]) > 0.5)
            enasf_alocadas = 0.0
            for eq in S_Equipes_ENASF
                if value(eq_ENASF_n1[eq, n1]) > 0
                    enasf_alocadas += value(eq_ENASF_n1[eq, n1]) 
                end
            end

            enasf_criadas = round(value(eq_enasf_criadas[n1]), digits=2)
            println("  ENASF: $enasf_alocadas alocadas, $enasf_criadas criadas")
        end
    
        # 4. População Atendida e Coberta por ENASF
        println("\n=== População Atendida ===")
        for d in S_Pontos_Demanda
            for n1 in dominio_atr_n1[d]
                for eq in S_equipes
                    pop = 0
                    if pop > 0
                        println("Ponto $d, Equipe $eq, UBS $n1: $pop atendida")
                    end
                end
                pop_enasf = round(value(pop_coberta_ENASF[d, n1]), digits=2)
                if pop_enasf > 0
                    println("Ponto $d, UBS $n1: $pop_enasf coberta por ENASF")
                end
            end
        end


        # 5. Fluxos para Níveis Secundário e Terciário
        println("\n=== Fluxos para Nível Secundário (n2) ===")
        for n1 in S_n1
            for n2 in dominio_atr_n2[n1]
                fluxo = round(value(X_n2[n1, n2]), digits=2)
                if fluxo > 0
                    println("De UBS $n1 para n2 $n2: $fluxo")
                end
            end
        end
        println("\n=== Fluxos para Nível Terciário (n3) ===")
        for n2 in S_n2
            for n3 in dominio_atr_n3[n2]
                fluxo = round(value(X_n3[n2, n3]), digits=2)
                if fluxo > 0
                    println("De n2 $n2 para n3 $n3: $fluxo")
                end
            end
        end

        # 6. Custos
        println("\n=== Custos ===")
        println("Custo Total: ", round(value(custo_total), digits=2))
        println("  Contratação: ", round(value(custo_contratacao), digits=2))
        println("  Realocação: ", round(value(custo_realocaca_equipes), digits=2))
        println("  Mensal Equipes: ", round(value(custo_mensal_equipes), digits=2))
        println("  Fixo: ", round(value(custo_fixo), digits=2))
        println("  Abertura: ", round(value(custo_abertura), digits=2))

    else
        println("Otimização não convergiu. Status: ", termination_status(model))
    end

    

end




function generate_warm_start(model, S_Pontos_Demanda, S_n1, S_instalacoes_reais_n1, S_locais_candidatos_n1, 
    S_Equipes_ESF, S_Equipes_ESB, S_Equipes_ENASF, dominio_atr_n1, S_Valor_Demanda, 
    Matriz_Dist_n1, S_origem_equipes_ESF, S_origem_equipes_ESB, S_origem_equipes_ENASF, 
    S_equipes, dominio_UBS_Emulti, Orcamento_Maximo, percent_n1_n2, percent_n2_n3, S_n2, 
    S_n3, dominio_atr_n2, dominio_atr_n3, S_IVS)

    Random.seed!(1234)  # Ensure reproducibility

    # Initialize dictionaries for variable values
    Aloc_val = Dict{Tuple{Any,Any},Float64}()
    Abr_n1_val = Dict{Any,Float64}()
    eq_ESF_n1_val = Dict{Tuple{Any,Any},Float64}()
    eq_ESB_n1_val = Dict{Tuple{Any,Any},Float64}()
    eq_ENASF_n1_val = Dict{Tuple{Any,Any},Float64}()
    pop_atendida_val = Dict{Tuple{Any,Any,Any},Float64}()
    pop_coberta_ENASF_val = Dict{Tuple{Any,Any},Float64}()
    eq_ESF_criadas_val = Dict{Any,Float64}()
    eq_ESB_criadas_val = Dict{Any,Float64}()
    eq_enasf_criadas_val = Dict{Any,Float64}()
    fluxo_n2_val = Dict{Tuple{Any,Any},Float64}()
    fluxo_n3_val = Dict{Tuple{Any,Any},Float64}()
    cobertura_ENASF_val = Dict{Any,Float64}()

    # Step 1: Open only existing units to minimize costs
    for n1 in S_n1
    Abr_n1_val[n1] = n1 in S_instalacoes_reais_n1 ? 1.0 : 0.0
    end

    # Step 2: Assign demand points to the closest open unit
    unassigned_demand = Set(S_Pontos_Demanda)
    for d in S_Pontos_Demanda
    min_dist = Inf
    closest_n1 = nothing
    for n1 in dominio_atr_n1[d]
    if Abr_n1_val[n1] == 1.0 && Matriz_Dist_n1[d, n1] < min_dist
    min_dist = Matriz_Dist_n1[d, n1]
    closest_n1 = n1
    end
    end
    if closest_n1 !== nothing
    for n1 in dominio_atr_n1[d]
    Aloc_val[(d, n1)] = (n1 == closest_n1) ? 1.0 : 0.0
    end
    delete!(unassigned_demand, d)
    end
    end

    # Step 3: Open candidate units only if necessary and budget allows
    max_budget = Orcamento_Maximo * 4
    fixed_cost = sum(Abr_n1_val[n1] * 1500 for n1 in S_n1)
    opening_cost = 0.0
    remaining_budget = max_budget - fixed_cost

    for d in unassigned_demand
    min_dist = Inf
    closest_n1 = nothing
    for n1 in dominio_atr_n1[d]
    if n1 in S_locais_candidatos_n1 && Matriz_Dist_n1[d, n1] < min_dist && remaining_budget >= 10000
    min_dist = Matriz_Dist_n1[d, n1]
    closest_n1 = n1
    end
    end
    if closest_n1 !== nothing
    Abr_n1_val[closest_n1] = 1.0
    opening_cost += 10000
    remaining_budget -= 10000
    for n1 in dominio_atr_n1[d]
    Aloc_val[(d, n1)] = (n1 == closest_n1) ? 1.0 : 0.0
    end
    delete!(unassigned_demand, d)
    end
    end

    # Step 4: Allocate ESF and ESB teams
    for n1 in S_n1
    if Abr_n1_val[n1] == 1.0
    eq_ESF_criadas_val[n1] = 0.0
    eq_ESB_criadas_val[n1] = 0.0
    # Calculate total demand assigned to this unit (50% of original demand)
    total_demand = sum(0.5 * S_Valor_Demanda[d] * get(Aloc_val, (d, n1), 0.0) for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]; init=0.0)
    # Estimate number of ESF teams needed (max 2 to stay within budget)
    num_ESF_needed = ceil(Int, total_demand / 3000)
    num_ESF_needed = min(num_ESF_needed, 2)  # Limit to 2 teams to reduce costs
    # Check if assigning teams fits within budget
    esf_cost_per_team = 32000 + sum(Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * 100 for eq in S_Equipes_ESF; init=0.0) / max(1, length(S_Equipes_ESF))
    if num_ESF_needed * esf_cost_per_team <= remaining_budget
    available_teams_ESF = [eq for eq in S_Equipes_ESF if sum(get(eq_ESF_n1_val, (eq, j), 0.0) for j in S_n1; init=0.0) == 0]
    num_ESF_teams = min(num_ESF_needed, length(available_teams_ESF))
    for eq in S_Equipes_ESF
    eq_ESF_n1_val[(eq, n1)] = 0.0
    end
    for i in 1:num_ESF_teams
    eq_ESF_n1_val[(available_teams_ESF[i], n1)] = 1.0
    remaining_budget -= esf_cost_per_team
    end
    # Assign ESB teams to match ESF teams
    available_teams_ESB = [eq for eq in S_Equipes_ESB if sum(get(eq_ESB_n1_val, (eq, j), 0.0) for j in S_n1; init=0.0) == 0]
    num_ESB_teams = min(num_ESF_teams, length(available_teams_ESB))
    esb_cost_per_team = 32000 + sum(Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * 100 for eq in S_Equipes_ESB; init=0.0) / max(1, length(S_Equipes_ESB))
    for eq in S_Equipes_ESB
    eq_ESB_n1_val[(eq, n1)] = 0.0
    end
    for i in 1:num_ESB_teams
    if esb_cost_per_team <= remaining_budget
    eq_ESB_n1_val[(available_teams_ESB[i], n1)] = 1.0
    remaining_budget -= esb_cost_per_team
    end
    end
    else
    for eq in S_Equipes_ESF
    eq_ESF_n1_val[(eq, n1)] = 0.0
    end
    for eq in S_Equipes_ESB
    eq_ESB_n1_val[(eq, n1)] = 0.0
    end
    end
    else
    eq_ESF_criadas_val[n1] = 0.0
    eq_ESB_criadas_val[n1] = 0.0
    for eq in S_Equipes_ESF
    eq_ESF_n1_val[(eq, n1)] = 0.0
    end
    for eq in S_Equipes_ESB
    eq_ESB_n1_val[(eq, n1)] = 0.0
    end
    end
    end

    # Step 5: Assign population to teams (50% of demand)
    for n1 in S_n1
    if Abr_n1_val[n1] == 1.0
    # Calculate total ESF and ESB capacity
    esf_capacity = 3000 * sum(get(eq_ESF_n1_val, (eq, n1), 0.0) for eq in S_Equipes_ESF; init=0.0)
    esb_capacity = 3000 * sum(get(eq_ESB_n1_val, (eq, n1), 0.0) for eq in S_Equipes_ESB; init=0.0)
    # Distribute 50% of demand across assigned demand points
    assigned_demand_points = [d for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d] && get(Aloc_val, (d, n1), 0.0) == 1.0]
    for d in assigned_demand_points
    for eq in S_equipes
    pop_atendida_val[(d, eq, n1)] = 0.0
    if eq == 1 && esf_capacity > 0
    pop_atendida_val[(d, eq, n1)] = min(0.5 * S_Valor_Demanda[d], esf_capacity)
    esf_capacity -= pop_atendida_val[(d, eq, n1)]
    elseif eq == 2 && esb_capacity > 0
    pop_atendida_val[(d, eq, n1)] = min(0.5 * S_Valor_Demanda[d], esb_capacity)
    esb_capacity -= pop_atendida_val[(d, eq, n1)]
    end
    end
    end
    else
    for d in S_Pontos_Demanda
    for eq in S_equipes
    if n1 in dominio_atr_n1[d]
    pop_atendida_val[(d, eq, n1)] = 0.0
    end
    end
    end
    end
    end

    # Step 6: Assign ENASF teams and coverage
    for n1 in S_n1
    if Abr_n1_val[n1] == 1.0 && sum(get(eq_ESF_n1_val, (eq, n1), 0.0) for eq in S_Equipes_ESF; init=0.0) >= 1
    # Check if ENASF team fits within budget
    enasf_cost = 40000 + 90000
    if remaining_budget >= enasf_cost
    cobertura_ENASF_val[n1] = 1.0
    eq_enasf_criadas_val[n1] = 1.0
    remaining_budget -= enasf_cost
    for eq in S_Equipes_ENASF
    eq_ENASF_n1_val[(eq, n1)] = 0.0
    end
    else
    cobertura_ENASF_val[n1] = 0.0
    eq_enasf_criadas_val[n1] = 0.0
    for eq in S_Equipes_ENASF
    eq_ENASF_n1_val[(eq, n1)] = 0.0
    end
    end
    else
    cobertura_ENASF_val[n1] = 0.0
    eq_enasf_criadas_val[n1] = 0.0
    for eq in S_Equipes_ENASF
    eq_ENASF_n1_val[(eq, n1)] = 0.0
    end
    end
    end

    # Step 7: Set ENASF-covered population
    for d in S_Pontos_Demanda
    for n1 in dominio_atr_n1[d]
    pop_coberta_ENASF_val[(d, n1)] = 0.0
    if get(Aloc_val, (d, n1), 0.0) == 1.0 && cobertura_ENASF_val[n1] == 1.0
    pop_coberta_ENASF_val[(d, n1)] = get(pop_atendida_val, (d, 1, n1), 0.0)
    end
    end
    end

    # Step 8: Set secondary and tertiary flows
    for n1 in S_n1
    for n2 in dominio_atr_n2[n1]
    fluxo_n2_val[(n1, n2)] = percent_n1_n2 * sum(get(pop_atendida_val, (d, eq, n1), 0.0) for eq in S_equipes, d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]; init=0.0)
    end
    end
    for n2 in S_n2
    for n3 in dominio_atr_n3[n2]
    fluxo_n3_val[(n2, n3)] = percent_n2_n3 * sum(get(fluxo_n2_val, (n1, n2), 0.0) for n1 in S_n1 if n2 in dominio_atr_n2[n1]; init=0.0)
    end
    end

    # Step 9: Apply warm start to the model
    od = JuMP.object_dictionary(model)
    if haskey(od, :Aloc_)
        for (d, n1) in keys(od[:Aloc_])
            set_start_value(od[:Aloc_][d, n1], get(Aloc_val, (d, n1), 0.0))
        end
    end
    if haskey(od, :Abr_n1)
        for n1 in keys(od[:Abr_n1])
            set_start_value(od[:Abr_n1][n1], get(Abr_n1_val, n1, 0.0))
        end
    end
    if haskey(od, :eq_ESF_n1)
        for (eq, n1) in keys(od[:eq_ESF_n1])
            set_start_value(od[:eq_ESF_n1][eq, n1], get(eq_ESF_n1_val, (eq, n1), 0.0))
        end
    end
    if haskey(od, :eq_ESB_n1)
        for (eq, n1) in keys(od[:eq_ESB_n1])
            set_start_value(od[:eq_ESB_n1][eq, n1], get(eq_ESB_n1_val, (eq, n1), 0.0))
        end
    end
    if haskey(od, :eq_ENASF_n1)
        for (eq, n1) in keys(od[:eq_ENASF_n1])
            set_start_value(od[:eq_ENASF_n1][eq, n1], get(eq_ENASF_n1_val, (eq, n1), 0.0))
        end
    end
    if haskey(od, :pop_atendida)
        for (d, eq, n1) in keys(od[:pop_atendida])
            set_start_value(od[:pop_atendida][d, eq, n1], get(pop_atendida_val, (d, eq, n1), 0.0))
        end
    end
    if haskey(od, :pop_coberta_ENASF)
        for (d, n1) in keys(od[:pop_coberta_ENASF])
            set_start_value(od[:pop_coberta_ENASF][d, n1], get(pop_coberta_ENASF_val, (d, n1), 0.0))
        end
    end
    if haskey(od, :eq_ESF_criadas)
        for n1 in keys(od[:eq_ESF_criadas])
            set_start_value(od[:eq_ESF_criadas][n1], get(eq_ESF_criadas_val, n1, 0.0))
        end
    end
    if haskey(od, :eq_ESB_criadas)
        for n1 in keys(od[:eq_ESB_criadas])
            set_start_value(od[:eq_ESB_criadas][n1], get(eq_ESB_criadas_val, n1, 0.0))
        end
    end
    if haskey(od, :eq_enasf_criadas)
        for n1 in keys(od[:eq_enasf_criadas])
            set_start_value(od[:eq_enasf_criadas][n1], get(eq_enasf_criadas_val, n1, 0.0))
        end
    end
    if haskey(od, :X_n2)
        for (n1, n2) in keys(od[:X_n2])
            set_start_value(od[:X_n2][n1, n2], get(fluxo_n2_val, (n1, n2), 0.0))
        end
    end
    if haskey(od, :X_n3)
        for (n2, n3) in keys(od[:X_n3])
            set_start_value(od[:X_n3][n2, n3], get(fluxo_n3_val, (n2, n3), 0.0))
        end
    end
    if haskey(od, :cobertura_ENASF)
        for n1 in keys(od[:cobertura_ENASF])
            set_start_value(od[:cobertura_ENASF][n1], get(cobertura_ENASF_val, n1, 0.0))
        end
    end

    # Step 10: Calculate and print estimated costs
    custo_total = sum(get(eq_ESF_criadas_val, n1, 0.0) * 30000 for n1 in S_n1) +
    sum(Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * get(eq_ESF_n1_val, (eq, n1), 0.0) * 100 for eq in S_Equipes_ESF, n1 in S_n1) +
    sum(get(eq_ESF_n1_val, (eq, n1), 0.0) * 32000 for eq in S_Equipes_ESF, n1 in S_n1) +
    sum(get(eq_ESB_criadas_val, n1, 0.0) * 30000 for n1 in S_n1) +
    sum(Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * get(eq_ESB_n1_val, (eq, n1), 0.0) * 100 for eq in S_Equipes_ESB, n1 in S_n1) +
    sum(get(eq_ESB_n1_val, (eq, n1), 0.0) * 32000 for eq in S_Equipes_ESB, n1 in S_n1) +
    sum(get(eq_enasf_criadas_val, n1, 0.0) * 40000 for n1 in S_n1) +
    sum(Matriz_Dist_n1[S_origem_equipes_ENASF[eq], n1] * get(eq_ENASF_n1_val, (eq, n1), 0.0) * 100 for eq in S_Equipes_ENASF, n1 in S_n1) +
    sum((get(eq_ENASF_n1_val, (eq, n1), 0.0) + get(eq_enasf_criadas_val, n1, 0.0)) * 90000 for eq in S_Equipes_ENASF, n1 in S_n1) +
    fixed_cost + opening_cost
    println("Estimated custo_total: ", custo_total, " vs Max: ", max_budget)
    if custo_total > max_budget
    println("WARNING: Budget exceeded in warm start. Consider reducing teams or units.")
    end

    return model
end




function create_optimization_model_maximal_coverage_fluxo_equipes_ESF_e_ESB_Juntas_NAO_RODA(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

    # Extrair dados para facilitar a leitura e escrita do modelo!
    S_n1 = indices.S_n1
    S_n2 = indices.S_n2
    S_n3 = indices.S_n3
    S_locais_candidatos_n1 = indices.S_Locais_Candidatos_n1
    S_instalacoes_reais_n1 = indices.S_instalacoes_reais_n1
    S_instalacoes_reais_n2 = indices.S_instalacoes_reais_n2
    S_instalacoes_reais_n3 = indices.S_instalacoes_reais_n3
    S_Pontos_Demanda = indices.S_Pontos_Demanda

    S_equipes_n2 = indices.S_equipes_n2
    S_equipes_n3 = indices.S_equipes_n3
    S_pacientes =  mun_data.constantes.S_pacientes
    S_Valor_Demanda = mun_data.S_Valor_Demanda
    porcentagem_populacao = mun_data.constantes.porcentagem_populacao
    S_IVS = parameters.IVS
    mt_emulti = parameters.S_Matriz_Dist.Matriz_Dist_Emulti
    dominio_atr_n1 = parameters.S_domains.dominio_n1

    #TODO: Retomar workarround de locais candidatos que atendam os pontos sem nenhum opcao no raio critico!
    dominio_candidatos_n1 = Dict(d => [s for s in dominio_atr_n1[d] if s in S_locais_candidatos_n1] for d in keys(dominio_atr_n1))
    dominio_UBS_Emulti = Dict(ubs_orig => [ubs_dest for ubs_dest in S_n1 if mt_emulti[ubs_orig, ubs_dest] <= 5] for ubs_orig in S_n1)



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

    Orcamento_Maximo = parameters.orcamento_maximo
    ponderador_Vulnerabilidade = parameters.ponderador_Vulnerabilidade
    S_IVS = ponderador_Vulnerabilidade .* parameters.IVS

    S_Equipes_ESF_Reais = indices.S_Equipes_ESF
    S_Equipes_ESB_Reais = indices.S_Equipes_ESB
    S_Equipes_ENASF_Reais = indices.S_Equipes_ENASF

    pop_total = sum(S_Valor_Demanda)
    eqps_nec_ESB = round((sum(S_Valor_Demanda)/3000) - length(S_Equipes_ESB_Reais)) + 1
    eqps_nec_ESF = round((sum(S_Valor_Demanda)/3000) - length(S_Equipes_ESF_Reais)) + 1
    eqps_ENAST = ((eqps_nec_ESF + length(S_Equipes_ESF_Reais) + 1) / 9)

    S_Equipes_ESF_Candidatas = collect(length(S_Equipes_ESF_Reais) + 1: length(S_Equipes_ESF_Reais) + 1 + eqps_nec_ESF)
    S_Equipes_ESB_Candidatas = collect(length(S_Equipes_ESB_Reais) + 1: length(S_Equipes_ESB_Reais) + 1 + eqps_nec_ESB)
    S_Equipes_ENASF_Candidatas = collect(length(S_Equipes_ENASF_Reais) + 1: length(S_Equipes_ENASF_Reais) + 1 + eqps_ENAST)


    S_Equipes_ENASF = vcat(S_Equipes_ENASF_Reais, S_Equipes_ENASF_Candidatas)
    S_Equipes_ESF = vcat(S_Equipes_ESF_Reais, S_Equipes_ESF_Candidatas)
    S_Equipes_ESB = vcat(S_Equipes_ESB_Reais, S_Equipes_ESB_Candidatas)

    S_origem_equipes_ESB = indices.S_origem_equipes_ESB
    S_origem_equipes_ESF = indices.S_origem_equipes_ESF
    S_origem_equipes_ENASF = indices.S_origem_equipes_ENASF #EQUIPE - NASF
    S_equipes = [1,2]

    #Indices de equipes candidatas criados!
    

    cap_equipes_n1 = 3000

    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", 3600.0)  # Reduzido para 10 minutos
    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-6) 
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)  # Reduzido para 5%
    set_optimizer_attribute(model, "threads", 4)  # Usar 4 threads
    set_optimizer_attribute(model, "presolve", "off")  # Ativar presolve 
    #Variaveis

    #atribuicao primária
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin) #Abertura unidades primárias
    #Tipo_equipe (ESF OU ESB), Indice da equipe, destino!
    #TODO - v0 so com ESF!!

    fluxo_eq_ESF_n1 = @variable(model, eq_ESF_n1[eq in S_Equipes_ESF, n1 in S_n1], Bin)   
    fluxo_eq_ESB_n1 = @variable(model, eq_ESB_n1[eq in S_Equipes_ESB, n1 in S_n1], Bin) 
    fluxo_eq_ENASF_n1 = @variable(model, eq_ENASF_n1[eq in S_Equipes_ENASF, n1 in S_n1], Bin) #Alocacao de ENASF em UBS
    #aloc_ESF_ENASF_n1 = @variable(model, aloc_ESF_ENASF[eq in S_Equipes_ENASF, eq1 in S_Equipes_ESF] >= 0 )  #Inicialmente continua!
    
    #aloc_ESF_ENASF_n1 = @variable(model, aloc_UBS_ENASF[ubs_origem in S_n1, ubs_com_enasf in dominio_ubs_ENASF[ubs_origem]], Bin) #Alocacao de UBS EM UBS
    
    var_pop_atendida = @variable(model, pop_atendida[d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]] >= 0) 
    

    #inicialmente vou somente encaminhar demanda para niveis superiore
    #Fluxo n2
    fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1]] >= 0)
    var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
    #Fluxo n3
    fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2]] >= 0)
    var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)



     # ============================================================================================================
    # VARIÁVEIS E RESTRIÇÕES PARA ALOCAÇÃO DE UBS NAS UBS MAIS PRÓXIMAS COM ENASF
    # ============================================================================================================


    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) <= 1)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] * maximum(S_Valor_Demanda))
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d])


    # ============================================================================================================
    # VARIÁVEIS E RESTRIÇÕES PARA ALOCAÇÃO DE UBS NAS UBS MAIS PRÓXIMAS COM ENASF
    # ============================================================================================================

    aloc_UBS_proxima_ENASF = @variable(model, aloc_UBS_proxima_ENASF[i in S_n1, j in dominio_UBS_Emulti[i]], Bin)
    
    
    # Equação 1: Cada UBS deve ser alocada a exatamente uma UBS com ENASF
    @constraint(model, [i in S_n1], sum(aloc_UBS_proxima_ENASF[i, j] for j in dominio_UBS_Emulti[i]) <= 1)
    
    # Equação 2: Só pode alocar a UBS j se ela tiver ENASF (y_j = 1)
    # y_j é representado por: existe alguma equipe ENASF alocada na UBS j
    @constraint(model, [i in S_n1, j in dominio_UBS_Emulti[i]], 
                aloc_UBS_proxima_ENASF[i, j] <= sum(eq_ENASF_n1[eq, j] for eq in S_Equipes_ENASF))


    #Toda UBS com ESF tem que estar alocada numa com emulti!
    #@constraint(model, [i in S_n1], sum(eq_ESF_n1[eq, i] for eq in S_Equipes_ESF) <= 
    #sum(aloc_UBS_proxima_ENASF[i, j] for j in dominio_UBS_Emulti[i]) * 200) 


    #Cada equipe ENASF so pode ser alocada em uma UBS!
    @constraint(model, [eq in S_Equipes_ENASF], sum(eq_ENASF_n1[eq, j] for j in S_n1) <= 1)
    @constraint(model, [i in S_n1, j in dominio_UBS_Emulti[i]], aloc_UBS_proxima_ENASF[i, j] <= Abr_n1[i])
    @constraint(model, [i in S_n1, j in dominio_UBS_Emulti[i]], aloc_UBS_proxima_ENASF[i, j] <= Abr_n1[j])
    

    # Garantir que uma UBS não se aloque a si mesma se não tiver ENASF
    @constraint(model, [i in S_n1], 
                aloc_UBS_proxima_ENASF[i, i] <= sum(eq_ENASF_n1[eq, i] for eq in S_Equipes_ENASF))
    
    #Quantidade de eq_enasf proporcional a ESF
    #@constraint(model, sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF, n1 in S_n1) <=  
                #sum(eq_ENASF_n1[eq, i] for eq in S_Equipes_ENASF, i in S_n1) * 9)

    #So posso alocar no maximo 4 ubs por ENASF para tentar distribuir os resultados!
    @constraint(model, [j in S_n1], sum(aloc_UBS_proxima_ENASF[i, j] for i in S_n1 if j in dominio_UBS_Emulti[i]) <= 4)


    
    
    # ------------------------------------------------------------------------------------------------------------------------------------
    # Ultima Tentativa da Tirar linearidade!!
    # -----------------------------------------------------------------------------------------------------------------------------------
    @variable(model, var_pop_ponderada_ENASF[n1 in S_n1] >= 0 )
    
    pop_atendida_por_UBS = @expression(model, [n1 in S_n1], 
    sum(pop_atendida[d, 1, n1] * S_IVS[d] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))
    
    aux_pop_aloc_ENASF = @variable(model, aux_pop_aloc_ENASF[n1 in S_n1, j in dominio_UBS_Emulti[n1]] >= 0)

    # Big-M mais preciso baseado na capacidade real
    max_ivs = maximum(S_IVS[d] for d in S_Pontos_Demanda)
    M = 4 * 3000 * max_ivs  # 4 equipes ESF × 3000 pessoas × maior IVS
    
    # RESTRIÇÕES DE LINEARIZAÇÃO CORRIGIDAS
    @constraint(model, [n1 in S_n1, j in dominio_UBS_Emulti[n1]], 
        aux_pop_aloc_ENASF[n1, j] <= M * aloc_UBS_proxima_ENASF[n1, j])  # CORRIGIDO: Big-M preciso
    
    @constraint(model, [n1 in S_n1, j in dominio_UBS_Emulti[n1]], 
        aux_pop_aloc_ENASF[n1, j] <= pop_atendida_por_UBS[n1])  # MANTÉM
    
    @constraint(model, [n1 in S_n1, j in dominio_UBS_Emulti[n1]], 
        aux_pop_aloc_ENASF[n1, j] >= pop_atendida_por_UBS[n1] - M * (1 - aloc_UBS_proxima_ENASF[n1, j]))  # CORRIGIDO: Big-M preciso
    
    # Restrição original linearizada (mantém igual)
    @constraint(model, [j in S_n1], 
        var_pop_ponderada_ENASF[j] == sum(aux_pop_aloc_ENASF[n1, j] for n1 in S_n1 if j in dominio_UBS_Emulti[n1]))

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Capacidades das UBS!
    # -----------------------------------------------------------------------------------------------------------------------------------

    #Cada unidade pode ter no maximo 4 equipes ESF e 4 equipes ESB!
    @constraint(model, [n1 in S_n1], sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) <= 4)

    #Cada unidade pode ter no maximo 1 Emulti!
    @constraint(model, [n1 in S_n1], sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF) <= 1)

    #Limite por equipes!
    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 1, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) * 3000)


    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 2, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) * 3000)


    # ------------------------------------------------------------------------------------------------------------------------------------
    # Alocacoes ESF - ESB
    # -----------------------------------------------------------------------------------------------------------------------------------

    @constraint(model, [n1 in S_n1], 
        sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB)  == sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF))

    #ESF e ESB Podema atender somente em uma UBS!
    @constraint(model, [eq in S_Equipes_ESF], sum(eq_ESF_n1[eq, n1] for n1 in S_n1) <= 1)
    @constraint(model, [eq in S_Equipes_ESB], sum(eq_ESB_n1[eq, n1] for n1 in S_n1) <= 1)


    
    # ------------------------------------------------------------------------------------------------------------------------------------
    # Abertura de unidades novas:
    # -----------------------------------------------------------------------------------------------------------------------------------

    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], Aloc_[d, s] <= var_abr_n1[s] )
    @constraint(model, [n1 in S_instalacoes_reais_n1], Abr_n1[n1] == 1)

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Restricoes de Custos
    # -----------------------------------------------------------------------------------------------------------------------------------
    @expression(model, custo_contratacao_equipes_esf, sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF_Candidatas, n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esf, sum((Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * eq_ESF_n1[eq, n1]) * 100 for eq in S_Equipes_ESF_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esf, sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF, n1 in S_n1) * 32000)


    @expression(model, custo_contratacao_equipes_esb, sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB_Candidatas, n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esb, sum((Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * eq_ESB_n1[eq, n1]) * 100  for eq in S_Equipes_ESB_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esb, sum(eq_ESB_n1[eq, n1]  for eq in S_Equipes_ESB, n1 in S_n1) * 32000)


    @expression(model, custo_contratacao_equipes_enasf, sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF_Candidatas, n1 in S_n1) * 40000)
    @expression(model, custo_realocaca_equipes_enasf, sum((Matriz_Dist_n1[S_origem_equipes_ENASF[eq], n1] * eq_ENASF_n1[eq, n1]) * 100  for eq in S_Equipes_ENASF_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_enasf, sum(eq_ENASF_n1[eq, n1]  for eq in S_Equipes_ENASF, n1 in S_n1) * 90000)


    @expression(model, custo_fixo, sum(Abr_n1[n1] * 1500 for n1 in S_n1))
    @expression(model, custo_abertura, sum(Abr_n1[n1] * 10000 for n1 in S_locais_candidatos_n1))

    
    @expression(model, custo_contratacao, custo_contratacao_equipes_esf + custo_contratacao_equipes_esb + custo_contratacao_equipes_enasf)
    @expression(model, custo_realocaca_equipes, custo_realocaca_equipes_esf + custo_realocaca_equipes_esb + custo_mensal_equipes_enasf)
    @expression(model, custo_mensal_equipes, custo_mensal_equipes_esf + custo_mensal_equipes_esb + custo_mensal_equipes_enasf )

    
    
    @expression(model, custo_total, 
    custo_contratacao
    + custo_realocaca_equipes 
    + custo_mensal_equipes
    + custo_fixo
    + custo_abertura
   )

    @constraint(model, custo_total <= Orcamento_Maximo * 2)

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Restricoes de Fluxo Hierarquico
    # -----------------------------------------------------------------------------------------------------------------------------------
    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
                sum(X_n2[n1, n2] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(pop_atendida[d, eq, n1] 
                        for  eq in S_equipes, d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))


    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
            sum(X_n3[n2, n3] for n3 in dominio_atr_n3[n2]) == 
            percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in dominio_atr_n2[n1]))
                    
    
    # ------------------------------------------------------------------------------------------------------------------------------------
    # Funcao Objetivo
    # -----------------------------------------------------------------------------------------------------------------------------------        
    @expression(model, pop_atendida_ESF, sum(pop_atendida[d, 1, un] * S_IVS[d] for d in S_Pontos_Demanda, un in S_n1 if un in dominio_atr_n1[d]) )
    @expression(model, pop_atendida_ESB, sum(pop_atendida[d, 2, un] * S_IVS[d] for d in S_Pontos_Demanda, un in S_n1 if un in dominio_atr_n1[d]) )
    @expression(model, pop_atendida_ENASF_FO, sum(var_pop_ponderada_ENASF[n1] for n1 in S_n1))
    #pop_atendida_ENASF

    @expression(model, pop_atendida_total, pop_atendida_ESF + pop_atendida_ESB + pop_atendida_ENASF_FO)
    #Funcao Objetivo:
    @objective(model, Max, pop_atendida_total)
    optimize!(model)
    obj = objective_value(model)
    # Coletar resultados das equipes ESF
    eval_results = true
    if eval_results == true
        optimize!(model)
        obj = objective_value(model)
        esf_results = DataFrame(
            Equipe = String[],
            Origem = String[],
            Destino = String[],
            Valor = Float64[]
        )

        for eq in S_Equipes_ESF
            for n1 in S_n1
                val = value(eq_ESF_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) ativada na unidade $(n1)")
                end
            end
        end

        


        for eq in S_Equipes_ESB
            for n1 in S_n1
                val = value(eq_ESB_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) ativada na unidade $(n1)")
                end
            end
        end

        
                
        for eq in S_Equipes_ENASF
            for n1 in S_n1
                val = value(eq_ENASF_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) alocada na unidade $(n1) com valor de $(val)")
                end
            end
        end 

        for i in S_n1
            for j in dominio_UBS_Emulti[i]
                val = value(aloc_UBS_proxima_ENASF[i,j])
                if val > 0
                    println("UBS $(i) alocada na unidade $(j) com valor de $(val)")
                end
            end     
        end

        # Mostrar total atendido por equipe (somando sobre todos os pontos de demanda e unidades)
  
        for n1 in S_n1
            if value(Abr_n1[n1]) > 0
                println(n1)
 
            end
        end
    end


    #Mudar indice para S_Equipes quando tiver 2 implementacoes - ESF e ESB

    return model

end



function create_optimization_model_maximal_coverage_fluxo_equipes_ESF_e_ESB_ENASF_simplificado_NAO_FUNCIONA(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

    # Extrair dados para facilitar a leitura e escrita do modelo!
    S_n1 = indices.S_n1
    S_n2 = indices.S_n2
    S_n3 = indices.S_n3
    S_locais_candidatos_n1 = indices.S_Locais_Candidatos_n1
    S_instalacoes_reais_n1 = indices.S_instalacoes_reais_n1
    S_instalacoes_reais_n2 = indices.S_instalacoes_reais_n2
    S_instalacoes_reais_n3 = indices.S_instalacoes_reais_n3
    S_Pontos_Demanda = indices.S_Pontos_Demanda

    S_equipes_n2 = indices.S_equipes_n2
    S_equipes_n3 = indices.S_equipes_n3
    S_pacientes =  mun_data.constantes.S_pacientes
    S_Valor_Demanda = mun_data.S_Valor_Demanda
    porcentagem_populacao = mun_data.constantes.porcentagem_populacao
    S_IVS = parameters.IVS
    mt_emulti = parameters.S_Matriz_Dist.Matriz_Dist_Emulti
    dominio_atr_n1 = parameters.S_domains.dominio_n1

    #TODO: Retomar workarround de locais candidatos que atendam os pontos sem nenhum opcao no raio critico!
    dominio_candidatos_n1 = Dict(d => [s for s in dominio_atr_n1[d] if s in S_locais_candidatos_n1] for d in keys(dominio_atr_n1))
    dominio_UBS_Emulti = Dict(ubs_orig => [ubs_dest for ubs_dest in S_n1 if mt_emulti[ubs_orig, ubs_dest] <= 5] for ubs_orig in S_n1)



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

    Orcamento_Maximo = parameters.orcamento_maximo
    ponderador_Vulnerabilidade = parameters.ponderador_Vulnerabilidade
    S_IVS = ponderador_Vulnerabilidade .* parameters.IVS

    S_Equipes_ESF_Reais = indices.S_Equipes_ESF
    S_Equipes_ESB_Reais = indices.S_Equipes_ESB
    S_Equipes_ENASF_Reais = indices.S_Equipes_ENASF

    pop_total = sum(S_Valor_Demanda)
    eqps_nec_ESB = round((sum(S_Valor_Demanda)/3000) - length(S_Equipes_ESB_Reais)) + 1
    eqps_nec_ESF = round((sum(S_Valor_Demanda)/3000) - length(S_Equipes_ESF_Reais)) + 1
    eqps_ENAST = ((eqps_nec_ESF + length(S_Equipes_ESF_Reais) + 1) / 9)

    S_Equipes_ESF_Candidatas = collect(length(S_Equipes_ESF_Reais) + 1: length(S_Equipes_ESF_Reais) + 1 + eqps_nec_ESF)
    S_Equipes_ESB_Candidatas = collect(length(S_Equipes_ESB_Reais) + 1: length(S_Equipes_ESB_Reais) + 1 + eqps_nec_ESB)
    S_Equipes_ENASF_Candidatas = collect(length(S_Equipes_ENASF_Reais) + 1: length(S_Equipes_ENASF_Reais) + 1 + eqps_ENAST)


    S_Equipes_ENASF = vcat(S_Equipes_ENASF_Reais, S_Equipes_ENASF_Candidatas)
    S_Equipes_ESF = vcat(S_Equipes_ESF_Reais, S_Equipes_ESF_Candidatas)
    S_Equipes_ESB = vcat(S_Equipes_ESB_Reais, S_Equipes_ESB_Candidatas)

    S_origem_equipes_ESB = indices.S_origem_equipes_ESB
    S_origem_equipes_ESF = indices.S_origem_equipes_ESF
    S_origem_equipes_ENASF = indices.S_origem_equipes_ENASF #EQUIPE - NASF
    S_equipes = [1,2]
    ubs_reais_com_setores = []
    for ubs in S_instalacoes_reais_n1
        setores_disponiveis = [d for d in S_Pontos_Demanda if ubs in dominio_atr_n1[d]]
        if !isempty(setores_disponiveis)
            push!(ubs_reais_com_setores, ubs)
        end
    end

        # DIAGNÓSTICO COMPLETO - executar ANTES de definir o modelo
    println("=== DIAGNÓSTICO DETALHADO DE FACTIBILIDADE ===")

    # 1. Verificar restrição ESF = ESB
    println("Verificando disponibilidade ESF vs ESB:")
    println("ESF disponíveis: $(length(S_Equipes_ESF))")
    println("ESB disponíveis: $(length(S_Equipes_ESB))")
    if length(S_Equipes_ESF) != length(S_Equipes_ESB)
        println("PROBLEMA: ESF ≠ ESB - restrição de igualdade é infactível")
    end

    # 2. Verificar se há equipes suficientes para demanda mínima
    demanda_total = sum(S_Valor_Demanda)
    equipes_necessarias_min = ceil(demanda_total / (4 * 3000))  # assumindo 4 equipes por UBS
    println("Demanda total: $demanda_total")
    println("Equipes mínimas necessárias: $equipes_necessarias_min")
    println("Equipes ESF disponíveis: $(length(S_Equipes_ESF))")

    # 3. Verificar orçamento vs custo mínimo realista
    custo_min_operacional = length(S_Equipes_ESF) * 32000 + length(S_Equipes_ESB) * 32000
    println("Custo operacional mínimo: $custo_min_operacional")
    println("Orçamento disponível: $(Orcamento_Maximo * 4)")
    println("Orçamento suficiente: $(custo_min_operacional <= Orcamento_Maximo * 4)")

    # 4. Verificar UBS reais vs setores
    ubs_problematicas = []
    for ubs in S_instalacoes_reais_n1
        setores = [d for d in S_Pontos_Demanda if ubs in dominio_atr_n1[d]]
        if isempty(setores)
            push!(ubs_problematicas, ubs)
        end
    end
    println("UBS reais sem setores disponíveis: $ubs_problematicas")
    #Indices de equipes candidatas criados!
    
    #Removendo ubs 61 dos dados para teste





    # --------------------------------------------------------------------------------
    #MODELO
    # --------------------------------------------------------------------------------
    model = Model(HiGHS.Optimizer)
    

    #atribuicao primária
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin) #Abertura unidades primárias
    #Tipo_equipe (ESF OU ESB), Indice da equipe, destino!
    #TODO - v0 so com ESF!!

    fluxo_eq_ESF_n1 = @variable(model, eq_ESF_n1[eq in S_Equipes_ESF, n1 in S_n1], Bin)   
    fluxo_eq_ESB_n1 = @variable(model, eq_ESB_n1[eq in S_Equipes_ESB, n1 in S_n1], Bin) 
    #fluxo_eq_ENASF_n1 = @variable(model, eq_ENASF_n1[eq in S_Equipes_ENASF, n1 in S_n1], Bin) #Alocacao de ENASF em UBS
    #aloc_ESF_ENASF_n1 = @variable(model, aloc_ESF_ENASF[eq in S_Equipes_ENASF, eq1 in S_Equipes_ESF] >= 0 )  #Inicialmente continua!
    
    #aloc_ESF_ENASF_n1 = @variable(model, aloc_UBS_ENASF[ubs_origem in S_n1, ubs_com_enasf in dominio_ubs_ENASF[ubs_origem]], Bin) #Alocacao de UBS EM UBS
    
    var_pop_atendida = @variable(model, pop_atendida[d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]] >= 0) 
    

    #inicialmente vou somente encaminhar demanda para niveis superiore
    #Fluxo n2
    fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1]] >= 0)
    var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
    #Fluxo n3
    fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2]] >= 0)
    var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)



     # ============================================================================================================
    # RESTRICOES DE TERRITORIZALICAO DAS UBS!
    # ============================================================================================================


    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) <= 1)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] * maximum(S_Valor_Demanda))
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d])
    @constraint(model, [n1 in S_instalacoes_reais_n1], Abr_n1[n1] == 1)

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Abertura de unidades novas:
    # -----------------------------------------------------------------------------------------------------------------------------------

    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], Aloc_[d, s] <= var_abr_n1[s] )



    #@constraint(model, [n1 in ubs_reais_com_setores], 
    #sum(Aloc_[d, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) >= 1)
    # ============================================================================================================
    # VERSÃO SIMPLIFICADA - VARIÁVEIS E RESTRIÇÕES ENASF
    # ============================================================================================================

    # VARIÁVEL 1: Cobertura ENASF para cada UBS (binária)
    #cobertura_ENASF = @variable(model, cobertura_ENASF[n1 in S_n1], Bin)
    
    # VARIÁVEL 2: População beneficiada por ENASF (contínua)
    #pop_ponderada_ubs = @variable(model, pop_ponderada_ubs[n1 in S_n1] >= 0)
   # beneficio_ENASF_linear = @variable(model, beneficio_ENASF_linear[n1 in S_n1] >= 0)
   #var_pop_atendida_EMULTI = @variable(model, var_pop_atendida_EMULTI[d in S_Pontos_Demanda] >= 0)
    # RESTRIÇÃO 1: Uma UBS tem cobertura ENASF se:
    # - Ela própria tem ENASF, OU
    # - Existe uma UBS próxima (≤5km) com ENASF e ambas estão abertas
    #@constraint(model, [n1 in S_n1],
      #  cobertura_ENASF[n1] <= 
      #  sum(eq_ENASF_n1[eq, j]  for j in dominio_UBS_Emulti[n1], eq in S_Equipes_ENASF)  # UBS próxima tem ENASF
    #)

   # @variable(model, setor_coberto_ENASF[d in S_Pontos_Demanda], Bin)

    # Um setor é coberto se pelo menos uma UBS que pode atendê-lo tem ENASF
    #@constraint(model, [d in S_Pontos_Demanda],
        #setor_coberto_ENASF[d] <= sum(cobertura_ENASF[n1] for n1 in S_n1 if n1 in dominio_atr_n1[d]))
    
    # População ENASF é a demanda ponderada por IVS dos setores cobertos
   # @constraint(model, [d in S_Pontos_Demanda], 
       # var_pop_atendida_EMULTI[d] <= S_Valor_Demanda[d] * S_IVS[d] * setor_coberto_ENASF[d])
    


    #So pode ter cobertura uma UBS Aberta!
    #@constraint(model, [n1 in S_n1], cobertura_ENASF[n1] <= Abr_n1[n1])
    #@constraint(model, [n1 in S_n1], sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF) <= Abr_n1[n1])


    # RESTRIÇÃO 4: Cada equipe ENASF só pode ser alocada em uma UBS
    #@constraint(model, [eq in S_Equipes_ENASF], 
     #   sum(eq_ENASF_n1[eq, n1] for n1 in S_n1) <= 1)

    # RESTRIÇÃO 5: Máximo 1 ENASF por UBS
   # @constraint(model, [n1 in S_n1], 
     #   sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF) <= 1)

    # RESTRIÇÃO 6: Limite de UBS atendidas por cada ENASF (distribuição)
    # Uma UBS com ENASF pode atender no máximo 9 outras UBS (baseado na proporção 1 ENASF:9 ESF)
    #@constraint(model, [j in S_n1],
   ## sum(cobertura_ENASF[i] for i in S_n1 if j in dominio_UBS_Emulti[i]) <= 
    #9 * sum(eq_ENASF_n1[eq, j] for eq in S_Equipes_ENASF))
    
    # 8. Definir população ponderada por UBS
    #@constraint(model, [n1 in S_n1],
        #pop_ponderada_ubs[n1] == sum(S_Valor_Demanda[d] * S_IVS[d] * cobertura_ENASF[n1] for d in S_Pontos_Demanda if Matriz_Dist_n1[d, n1] <= 5))
                        
    # 9. Linearização: beneficio = pop_ponderada * tem_ENASF
    #max_pop_possivel = 4 * 3000 * maximum(S_IVS)  # Big-M conservador
    #@constraint(model, [n1 in S_n1],
       # beneficio_ENASF_linear[n1] <= max_pop_possivel * cobertura_ENASF[n1])
    #@constraint(model, [n1 in S_n1],
        #beneficio_ENASF_linear[n1] <= pop_ponderada_ubs[n1])
    #@constraint(model, [n1 in S_n1],
        #beneficio_ENASF_linear[n1] >= pop_ponderada_ubs[n1] - max_pop_possivel * (1 - cobertura_ENASF[n1]))

    # 10. ATUALIZAR A FUNÇÃO OBJETIVO
    #@expression(model, pop_atendida_ENASF_FO, sum(var_pop_atendida_EMULTI[d] for d in S_Pontos_Demanda))


    # ------------------------------------------------------------------------------------------------------------------------------------
    # Capacidades das UBS!
    # -----------------------------------------------------------------------------------------------------------------------------------

    #Cada unidade pode ter no maximo 4 equipes ESF e 4 equipes ESB!
    @constraint(model, [n1 in S_n1], sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) <= 4)


    #Limite por equipes!
    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 1, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) * 3000)


    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 2, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) * 3000)


    # ------------------------------------------------------------------------------------------------------------------------------------
    # Alocacoes ESF - ESB
    # -----------------------------------------------------------------------------------------------------------------------------------

    @constraint(model, [n1 in S_n1], 
        sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB)  == sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF))

    #ESF e ESB Podema atender somente em uma UBS!
    @constraint(model, [eq in S_Equipes_ESF], sum(eq_ESF_n1[eq, n1] for n1 in S_n1) <= 1)
    @constraint(model, [eq in S_Equipes_ESB], sum(eq_ESB_n1[eq, n1] for n1 in S_n1) <= 1)


    

    

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Restricoes de Custos
    # -----------------------------------------------------------------------------------------------------------------------------------
    @expression(model, custo_contratacao_equipes_esf, sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF_Candidatas, n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esf, sum((Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * eq_ESF_n1[eq, n1]) * 100 for eq in S_Equipes_ESF_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esf, sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF, n1 in S_n1) * 32000)


    @expression(model, custo_contratacao_equipes_esb, sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB_Candidatas, n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esb, sum((Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * eq_ESB_n1[eq, n1]) * 100  for eq in S_Equipes_ESB_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esb, sum(eq_ESB_n1[eq, n1]  for eq in S_Equipes_ESB, n1 in S_n1) * 32000)


    #@expression(model, custo_contratacao_equipes_enasf, sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF_Candidatas, n1 in S_n1) * 40000)
    #@expression(model, custo_realocaca_equipes_enasf, sum((Matriz_Dist_n1[S_origem_equipes_ENASF[eq], n1] * eq_ENASF_n1[eq, n1]) * 100  for eq in S_Equipes_ENASF_Reais, n1 in S_n1 ))
    #@expression(model, custo_mensal_equipes_enasf, sum(eq_ENASF_n1[eq, n1]  for eq in S_Equipes_ENASF, n1 in S_n1) * 90000)


    @expression(model, custo_fixo, sum(Abr_n1[n1] * 1500 for n1 in S_n1))
    @expression(model, custo_abertura, sum(Abr_n1[n1] * 10000 for n1 in S_locais_candidatos_n1))

    
    @expression(model, custo_contratacao, custo_contratacao_equipes_esf + custo_contratacao_equipes_esb) #+ custo_contratacao_equipes_enasf)
    @expression(model, custo_realocaca_equipes, custo_realocaca_equipes_esf + custo_realocaca_equipes_esb) #+ custo_mensal_equipes_enasf)
    @expression(model, custo_mensal_equipes, custo_mensal_equipes_esf + custo_mensal_equipes_esb) #+ custo_mensal_equipes_enasf )

    
    
    @expression(model, custo_total, 
    custo_contratacao
    + custo_realocaca_equipes 
    + custo_mensal_equipes
    + custo_fixo
    + custo_abertura
   )

    @constraint(model, custo_total <= Orcamento_Maximo * 4)

    # ------------------------------------------------------------------------------------------------------------------------------------
    # Restricoes de Fluxo Hierarquico
    # -----------------------------------------------------------------------------------------------------------------------------------
    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
                sum(X_n2[n1, n2] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(pop_atendida[d, eq, n1] 
                        for  eq in S_equipes, d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))


    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
            sum(X_n3[n2, n3] for n3 in dominio_atr_n3[n2]) == 
            percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in dominio_atr_n2[n1]))
                    
    
    # ------------------------------------------------------------------------------------------------------------------------------------
    # Funcao Objetivo
    # -----------------------------------------------------------------------------------------------------------------------------------        
    @expression(model, pop_atendida_ESF, sum(pop_atendida[d, 1, un] * S_IVS[d] for d in S_Pontos_Demanda, un in S_n1 if un in dominio_atr_n1[d]) )
    @expression(model, pop_atendida_ESB, sum(pop_atendida[d, 2, un] * S_IVS[d] for d in S_Pontos_Demanda, un in S_n1 if un in dominio_atr_n1[d]) )
    #@expression(model, pop_atendida_ENASF_FO, sum(beneficio_ENASF[n1] for n1 in S_n1))
    #pop_atendida_ENASF

    @expression(model, pop_atendida_total, pop_atendida_ESF + pop_atendida_ESB) #+ pop_atendida_ENASF_FO)
    @objective(model, Max, pop_atendida_total)
    optimize!(model)


    

    # CONFIGURAÇÕES ADICIONAIS DO SOLVER HIGHS PARA APROVEITAR O WARM START
# Retirar configurações que podem não funcionar no HiGHS
    aplicar_warm_start_corrigido!(model)

    # Manter apenas configurações essenciais
    set_optimizer_attribute(model, "threads", 4)

    println("=== FASE 1: Busca inicial (Gap 15%) ===")
    set_optimizer_attribute(model, "mip_rel_gap", 0.25)  
    set_optimizer_attribute(model, "time_limit", 850.0)   
    optimize!(model)

    if termination_status(model) in [MOI.OPTIMAL, MOI.TIME_LIMIT]
        gap_atual = MOI.get(model, MOI.RelativeGap())
        println("Fase 1 concluída - GAP: $(round(100*gap_atual, digits=2))%")
        println("Valor objetivo atual: $(objective_value(model))")
        
        println("=== FASE 2: Refinamento (Gap 5%) ===")
        set_optimizer_attribute(model, "mip_rel_gap", 0.05)  
        set_optimizer_attribute(model, "time_limit", 1200.0) 
        optimize!(model)
        
        if termination_status(model) in [MOI.OPTIMAL, MOI.TIME_LIMIT]
            gap_final = MOI.get(model, MOI.RelativeGap())
            println("Fase 2 concluída - GAP final: $(round(100*gap_final, digits=2))%")
        end
    else
        println("Fase 1 não encontrou solução factível")
    end

    obj = objective_value(model)
    
    # Coletar resultados das equipes ESF
    eval_results = true
    if eval_results == true
        optimize!(model)
        obj = objective_value(model)
        esf_results = DataFrame(
            Equipe = String[],
            Origem = String[],
            Destino = String[],
            Valor = Float64[]
        )  

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

        total_enasf = 0.0
        for i in S_n1
            
            val = value(beneficio_ENASF[i])
            total_enasf += val
            println("UBS $(i): ", val)
        end

        println("Total Coberto ENASF $(total_enasf)")


        for eq in S_Equipes_ESF
            for n1 in S_n1
                val = value(eq_ESF_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) ativada na unidade $(n1)")
                end
            end
        end

        


        for eq in S_Equipes_ESB
            for n1 in S_n1
                val = value(eq_ESB_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) ativada na unidade $(n1)")
                end
            end
        end

        
                
        for eq in S_Equipes_ENASF
            for n1 in S_n1
                val = value(eq_ENASF_n1[eq, n1])
                if val > 0
                    #push!(esf_results, (string(eq), string(S_origem_equipes_ESF[eq]), string(n1), val))
                    println("Equipe $(eq) alocada na unidade $(n1) com valor de $(val)")
                end
            end
        end 

        for i in S_n1
                val = value(cobertura_ENASF[i])
                if val > 0
                    println("UBS $(i) com Cobertura ENASF")
                end  
        end

        # Mostrar total atendido por equipe (somando sobre todos os pontos de demanda e unidades)
  
        for n1 in S_n1
            if value(Abr_n1[n1]) > 0
                println(n1)
 
            end
        end
    end


    #Mudar indice para S_Equipes quando tiver 2 implementacoes - ESF e ESB

    return model

end



function create_optimization_model_maximal_coverage_fluxo_equipes_ULTIMA_TENTATIVA(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model

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

    Orcamento_Maximo = parameters.orcamento_maximo
    ponderador_Vulnerabilidade = parameters.ponderador_Vulnerabilidade
    S_IVS = ponderador_Vulnerabilidade .* parameters.IVS

    S_Equipes_ESF =  indices.S_Equipes_ESF
    S_Equipes_ESB =  indices.S_Equipes_ESB
    S_Equipes_ENASF = S_Equipes_ENASF_Reais = indices.S_Equipes_ENASF
    
    S_origem_equipes_ESB = indices.S_origem_equipes_ESB
    S_origem_equipes_ESF = indices.S_origem_equipes_ESF
    S_origem_equipes_ENASF = indices.S_origem_equipes_ENASF
    mt_emulti = parameters.S_Matriz_Dist.Matriz_Dist_Emulti
    dominio_UBS_Emulti = Dict(ubs_orig => [ubs_dest for ubs_dest in S_n1 if mt_emulti[ubs_orig, ubs_dest] <= 5] for ubs_orig in S_n1)


    cap_equipes_n1 = 3000

    model = Model(HiGHS.Optimizer)

    #Variaveis
    S_equipes = [1,2]
    #atribuicao primária
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin) #Abertura unidades primárias
    #Tipo_equipe (ESF OU ESB), Indice da equipe, destino!
    #TODO - v0 so com ESF!!

    fluxo_eq_ESF_n1 = @variable(model, eq_ESF_n1[eq in S_Equipes_ESF, n1 in S_n1], Bin) #Possibilidade de dividir a equipe ?
    fluxo_eq_ESB_n1 = @variable(model, eq_ESB_n1[eq in S_Equipes_ESB, n1 in S_n1], Bin) 
    eqs_ESF_criadas_n1 = @variable(model, eq_ESF_criadas[n1 in S_n1] >= 0)
    eqs_ESB_criadas_n1 = @variable(model, eq_ESB_criadas[n1 in S_n1] >= 0)
    var_pop_atendida = @variable(model, pop_atendida[d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]] >= 0) #Inserir aqui as demografias das populacoes!
    
    #inicialmente vou somente encaminhar demanda para niveis superiore
    #Fluxo n2
    fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1]] >= 0)
    var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
    #Fluxo n3
    fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2]] >= 0)
    var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)

    # ============================================================================================================
    # RESTRICOES DE TERRITORIZALICAO DAS UBS!
    # ============================================================================================================
    #Todas as unidades devem ser alocadas numa UBS de referencia
    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) <= 1)
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] *  S_Valor_Demanda[d])
    #@constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d])
        #Abertura de unidades novas:
    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], 
        Aloc_[d, s] <= var_abr_n1[s] )

    @constraint(model, [n1 in S_instalacoes_reais_n1], Abr_n1[n1] == 1)




    # ============================================================================================================
    # TUDO DE ENASF!!!
    # ============================================================================================================
        # VARIÁVEIS
        @variable(model, tem_ENASF[n1 in S_n1], Bin)  # UBS tem equipe ENASF
        @variable(model, atrib_ENASF[i in S_n1, j in dominio_UBS_Emulti[i]], Bin)  # UBS i é atendida por UBS j com ENASF
        @variable(model, pop_coberta_ENASF[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]] >= 0)
        fluxo_eq_ENASF_n1 = @variable(model, eq_ENASF_n1[eq in S_Equipes_ENASF, n1 in S_n1], Bin)
        @variable(model, eq_enasf_criadas[n1 in S_n1] >= 0)
        # RESTRIÇÕES

        # 1. UBS tem ENASF se recebe equipe
        @constraint(model, [j in S_n1],
            tem_ENASF[j] <= sum(eq_ENASF_n1[eq, j] for eq in S_Equipes_ENASF) + eq_enasf_criadas[j])

        # 2. Cada UBS pode ser atendida por no máximo uma UBS com ENASF
        @constraint(model, [i in S_n1],
            sum(atrib_ENASF[i, j] for j in S_n1 if j in dominio_UBS_Emulti[i]) <= 1)

        # 3. Só pode ser atendida por UBS que realmente tem ENASF
        @constraint(model, [i in S_n1, j in S_n1; j in dominio_UBS_Emulti[i]],
            atrib_ENASF[i, j] <= tem_ENASF[j])

        # 4. Só UBS abertas podem ser atribuídas e receber ENASF
        @constraint(model, [i in S_n1, j in S_n1; j in dominio_UBS_Emulti[i]],
            atrib_ENASF[i, j] <= Abr_n1[i])

        @constraint(model, [i in S_n1, j in S_n1; j in dominio_UBS_Emulti[i]],
            atrib_ENASF[i, j] <= Abr_n1[j])

        # 5. CAPACIDADE DE CADA ENASF - máximo 4 UBS por ENASF
        @constraint(model, [j in S_n1],
            sum(atrib_ENASF[i, j] for i in S_n1 if j in dominio_UBS_Emulti[i]) <= 
            4 * tem_ENASF[j])

        # 6. Linearização: pop_coberta = pop_atendida se tem atribuição ENASF
        M = maximum(S_Valor_Demanda)
        @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
            pop_coberta_ENASF[d, n1] <= sum(atrib_ENASF[n1, j] * M for j in S_n1 if j in dominio_UBS_Emulti[n1]))

        @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
            pop_coberta_ENASF[d, n1] <= pop_atendida[d, 1, n1])

        @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]],
            pop_coberta_ENASF[d, n1] >= pop_atendida[d, 1, n1] - 
            M * (1 - sum(atrib_ENASF[n1, j] for j in S_n1 if j in dominio_UBS_Emulti[n1])))

        # 7. Restrições de equipes ENASF (manter as existentes)
        @constraint(model, [n1 in S_n1], sum(eq_ENASF_n1[eq, n1] for eq in S_Equipes_ENASF) + eq_enasf_criadas[n1] <= 1)
        @constraint(model, [eq in S_Equipes_ENASF], sum(eq_ENASF_n1[eq, n1] for n1 in S_n1) <= 1)
        #@constraint(model, [n1 in S_n1], eq_enasf_criadas[n1] <= Abr_n1[n1])
        #@constraint(model, [eq in S_Equipes_ENASF, n1 in S_n1], eq_ENASF_n1[eq, n1] <= Abr_n1[n1])
    
    
    # ============================================================================================================
    # ============================================================================================================
    # ALOCACAO ESF E ESB
    # ============================================================================================================
    #Uma equipe so pode ser alocada em no maximo uma unidade!
    @constraint(model, [eq in S_Equipes_ESF], sum(eq_ESF_n1[eq, n1] for n1 in S_n1) <= 1)
    @constraint(model, [eq in S_Equipes_ESB], sum(eq_ESB_n1[eq, n1] for n1 in S_n1) <= 1)
 
    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 1, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= (sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) + eq_ESF_criadas[n1]) * 3000)


    @constraint(model, [n1 in S_n1], sum(var_pop_atendida[d, 2, n1] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) 
            <= (sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) + eq_ESB_criadas[n1]) * 3000)


    @constraint(model, [n1 in S_n1], sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF) + eq_ESF_criadas[n1] <= 4)


    @constraint(model, [n1 in S_n1], 
    sum(eq_ESB_n1[eq, n1] for eq in S_Equipes_ESB) + eq_ESB_criadas[n1]  
        == sum(eq_ESF_n1[eq, n1] for eq in S_Equipes_ESF) + eq_ESF_criadas[n1])



    #Equipes so podem ser alocadas em unidades abertas!
    @constraint(model, [eq in S_Equipes_ESF, n1 in S_n1], eq_ESF_n1[eq, n1] <= Abr_n1[n1])
    @constraint(model, [eq in S_Equipes_ESB, n1 in S_n1], eq_ESB_n1[eq, n1] <= Abr_n1[n1])
    #tambem preciso remover diminuir as equipes! - Posso assumir que se a equipe tiver custo negativo ela foi removida do sistema ?

    
    # ============================================================================================================
    # Restricao de Orcamento
    # ============================================================================================================
    @expression(model, custo_contratacao_equipes_esf, sum(eq_ESF_criadas[n1] for n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esf, sum((Matriz_Dist_n1[S_origem_equipes_ESF[eq], n1] * eq_ESF_n1[eq, n1]) * 1000 for eq in S_Equipes_ESF, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esf, (sum(eq_ESF_n1[eq, n1]  for eq in S_Equipes_ESF, n1 in S_n1) + sum(eq_ESF_criadas[n1] for n1 in S_n1))  * 32000)
    
    
    @expression(model, custo_contratacao_equipes_esb, sum(eq_ESB_criadas[n1] for n1 in S_n1) * 30000)
    @expression(model, custo_realocaca_equipes_esb, sum((Matriz_Dist_n1[S_origem_equipes_ESB[eq], n1] * eq_ESB_n1[eq, n1]) * 1000  for eq in S_Equipes_ESB, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_esb, (sum(eq_ESB_n1[eq, n1]  for eq in S_Equipes_ESB, n1 in S_n1) + sum(eq_ESB_criadas[n1] for n1 in S_n1)) * 32000)


    @expression(model, custo_contratacao_equipes_enasf, sum(eq_enasf_criadas[n1] for  n1 in S_n1) * 40000)
    @expression(model, custo_realocaca_equipes_enasf, sum((Matriz_Dist_n1[S_origem_equipes_ENASF[eq], n1] * eq_ENASF_n1[eq, n1]) * 1000  for eq in S_Equipes_ENASF_Reais, n1 in S_n1 ))
    @expression(model, custo_mensal_equipes_enasf, (sum(eq_ENASF_n1[eq, n1]  for eq in S_Equipes_ENASF, n1 in S_n1) + sum(eq_enasf_criadas[n1] for  n1 in S_n1)) * 90000)



    @expression(model, custo_fixo, sum(Abr_n1[n1] * 1500 for n1 in S_n1))
    @expression(model, custo_abertura, sum(Abr_n1[n1] * 10000 for n1 in S_locais_candidatos_n1))
    

    @expression(model, custo_contratacao, custo_contratacao_equipes_esf + custo_contratacao_equipes_esb + custo_contratacao_equipes_enasf)
    @expression(model, custo_realocaca_equipes, custo_realocaca_equipes_esf + custo_realocaca_equipes_esb + custo_mensal_equipes_enasf)
    @expression(model, custo_mensal_equipes, custo_mensal_equipes_esf + custo_mensal_equipes_esb + custo_mensal_equipes_enasf)


    @expression(model, custo_total, 
    custo_contratacao
    + custo_realocaca_equipes 
    + custo_mensal_equipes
    + custo_fixo
    + custo_abertura
   )

    @constraint(model, custo_total <= Orcamento_Maximo * 3)

    # ============================================================================================================
    # Multi-Fluxo
    # ============================================================================================================

    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
                sum(X_n2[n1, n2] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(pop_atendida[d, 1, n1] 
                        for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))


    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
            sum(X_n3[n2, n3] for n3 in dominio_atr_n3[n2]) == 
            percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in dominio_atr_n2[n1]))
                    

    #Funcao Objetivo:
    @objective(model, Max, sum(pop_atendida[d, eq, un] * S_IVS[d] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d]) 
    + sum(pop_coberta_ENASF[d, n1] * S_IVS[d] for d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]))
    #+ sum(var_equidade[eq] * vls_eq[eq] for eq in S_equipes)

    

    # =============================================================================================================
    # Tentativa warm START
    # =============================================================================================================

    #Random.seed!(1234)
    #model = Model(HiGHS.Optimizer)
    #set_optimizer_attribute(model, "random_seed", 1234)
    warm_start_ENASF_inteligente!(model)

    set_optimizer_attribute(model, "time_limit", 1800.0)  # 30 min
    set_optimizer_attribute(model, "mip_rel_gap", 0.15)   # Gap relaxado
    set_optimizer_attribute(model, "threads", 8)
    set_optimizer_attribute(model, "presolve", "on")

    optimize!(model)

    # ============================================================================================================
    # Solve
    # ============================================================================================================

    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "dual_feasibility_tolerance", 1e-4)
    set_optimizer_attribute(model, "time_limit", 900.0)
    set_optimizer_attribute(model, "mip_rel_gap", 0.05)
    # ... (your model definition)

    optimize!(model)

    

    # ============================================================================================================
    # Pos-OTM
    # ============================================================================================================

    if termination_status(model) == MOI.OPTIMAL
        println("=== Solução Ótima Encontrada ===")
        println("Valor do Objetivo: ", objective_value(model))
        


        #pop_atendida_ENSF = value.(model[:pop_coberta_ENASF])
        total_eq = 0.0
        for d in indices.S_Pontos_Demanda, n1 in indices.S_n1
            if n1 in parameters.S_domains.dominio_n1[d]
                total_eq += value(pop_coberta_ENASF[d,n1])
            end
        end
          println("Pop coberta por enasf: ", total_eq)
        

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
  

        # 1. UBS Abertas (Abr_n1)
        println("\n=== UBS Abertas ===")
        for n1 in S_n1
            if value(Abr_n1[n1]) > 0.5  # Binário, tolerância para 1
                println("UBS $n1: Aberta")
            else
                println("UBS $n1: Fechada")
            end
        end
    
        # 2. Alocação de Pontos de Demanda
        println("\n=== Alocação de Demanda para UBS ===")
        for d in S_Pontos_Demanda
            alocado = false
            for n1 in dominio_atr_n1[d]
                if value(Aloc_[d, n1]) > 0.5
                    println("Ponto $d alocado para UBS $n1")
                    alocado = true
                end
            end
            if !alocado
                println("Ponto $d NÃO alocado")
            end
        end
        

        enasf_alocadas = 0.0
        for eq in S_Equipes_ENASF, n1 in S_n1
            if value(eq_ENASF_n1[eq, n1]) > 0
                println("Equipe $eq alocado na UBS $n1 com valor de $(value(eq_ENASF_n1[eq, n1]))")
            end
        end


        
        
        for eq in S_Equipes_ESF, n1 in S_n1
            if value(eq_ESF_n1[eq, n1]) > 0
                println("Equipe $eq alocado na UBS $n1 com valor de $(value(eq_ESF_n1[eq, n1]))")
            end
        end


        # Soma total da variável eq_ESF_criadas[n1] para todas as UBS
        total_esf_criadas = sum(value(eq_ESF_criadas[n1]) for n1 in S_n1)
        println("\nTotal de ESF criadas: ", total_esf_criadas)

        total_esb_criadas = sum(value(eq_ESB_criadas[n1]) for n1 in S_n1)
        println("\nTotal de ESB criadas: ", total_esb_criadas)

        total_enasf_criadas = sum(value(eq_enasf_criadas[n1]) for n1 in S_n1)
        println("\nTotal de enasf criadas: ", total_enasf_criadas)

        # 3. Equipes Alocadas e Criadas
        println("\n=== Equipes Alocadas e Criadas por UBS ===")
        for n1 in S_n1
            println("\nUBS $n1:")
            # ESF
            esf_alocadas = 0.0
            for eq in S_Equipes_ESF
                if value(eq_ESF_n1[eq, n1]) > 0
                    esf_alocadas += value(eq_ESF_n1[eq, n1]) 
                end
            end
            #esf_alocadas = sum(value(eq_ESF_n1[eq, n1]) for eq in S_Equipes_ESF if value(eq_ESF_n1[eq, n1]) > 0.5)
            esf_criadas = round(value(eq_ESF_criadas[n1]), digits=2)
            println("  ESF: $esf_alocadas alocadas, $esf_criadas criadas")
            # ESB

            esb_alocadas = 0.0
            for eq in S_Equipes_ESB
                if value(eq_ESB_n1[eq, n1]) > 0
                    esb_alocadas += value(eq_ESB_n1[eq, n1]) 
                end
            end
            #esb_alocadas = sum(value(eq_ESB_n1[eq, n1]) for eq in S_Equipes_ESB if value(eq_ESB_n1[eq, n1]) > 0.5)
            esb_criadas = round(value(eq_ESB_criadas[n1]), digits=2)
            println("  ESB: $esb_alocadas alocadas, $esb_criadas criadas")
            # ENASF
            #enasf_alocadas = sum(value(eq_ENASF_n1[eq, n1]) for eq in S_Equipes_ENASF if value(eq_ENASF_n1[eq, n1]) > 0.5)
            enasf_alocadas = 0.0
            for eq in S_Equipes_ENASF
                if value(eq_ENASF_n1[eq, n1]) > 0
                    enasf_alocadas += value(eq_ENASF_n1[eq, n1]) 
                end
            end

            enasf_criadas = round(value(eq_enasf_criadas[n1]), digits=2)
            println("  ENASF: $enasf_alocadas alocadas, $enasf_criadas criadas")
        end
    
        # 4. População Atendida e Coberta por ENASF
        println("\n=== População Atendida ===")
        for d in S_Pontos_Demanda
            for n1 in dominio_atr_n1[d]
                for eq in S_equipes
                    pop = 0
                    if pop > 0
                        println("Ponto $d, Equipe $eq, UBS $n1: $pop atendida")
                    end
                end
                pop_enasf = round(value(pop_coberta_ENASF[d, n1]), digits=2)
                if pop_enasf > 0
                    println("Ponto $d, UBS $n1: $pop_enasf coberta por ENASF")
                end
            end
        end


        # 5. Fluxos para Níveis Secundário e Terciário
        println("\n=== Fluxos para Nível Secundário (n2) ===")
        for n1 in S_n1
            for n2 in dominio_atr_n2[n1]
                fluxo = round(value(X_n2[n1, n2]), digits=2)
                if fluxo > 0
                    println("De UBS $n1 para n2 $n2: $fluxo")
                end
            end
        end
        println("\n=== Fluxos para Nível Terciário (n3) ===")
        for n2 in S_n2
            for n3 in dominio_atr_n3[n2]
                fluxo = round(value(X_n3[n2, n3]), digits=2)
                if fluxo > 0
                    println("De n2 $n2 para n3 $n3: $fluxo")
                end
            end
        end

        # 6. Custos
        println("\n=== Custos ===")
        println("Custo Total: ", round(value(custo_total), digits=2))
        println("  Contratação: ", round(value(custo_contratacao), digits=2))
        println("  Realocação: ", round(value(custo_realocaca_equipes), digits=2))
        println("  Mensal Equipes: ", round(value(custo_mensal_equipes), digits=2))
        println("  Fixo: ", round(value(custo_fixo), digits=2))
        println("  Abertura: ", round(value(custo_abertura), digits=2))

    else
        println("Otimização não convergiu. Status: ", termination_status(model))
    end

    return model

end



function warm_start_ENASF_inteligente!(model)
    println("=== WARM START PARA MODELO ENASF COMPLEXO ===")
    
    # 1. WARM START BÁSICO (UBS reais abertas)
    for ubs in S_instalacoes_reais_n1
        set_start_value(var_abr_n1[ubs], 1.0)
    end
    
    # 2. ESTRATÉGIA ENASF: Alocar ENASFs nas UBS com maior demanda ponderada
    demanda_ponderada_ubs = Dict{Int, Float64}()
    for ubs in S_n1
        demanda_total = 0.0
        for d in S_Pontos_Demanda
            if ubs in dominio_atr_n1[d]
                demanda_total += S_Valor_Demanda[d] * S_IVS[d]
            end
        end
        demanda_ponderada_ubs[ubs] = demanda_total
    end
    
    # Selecionar UBS para receber ENASF (distribuídas geograficamente)
    ubs_enasf_candidatas = sort(collect(S_n1), by = ubs -> demanda_ponderada_ubs[ubs], rev = true)
    ubs_com_enasf = Set{Int}()
    
    # Alocar ENASFs com distância mínima entre elas (evitar concentração)
    for ubs in ubs_enasf_candidatas
        pode_alocar = true
        for ubs_existente in ubs_com_enasf
            if mt_emulti[ubs, ubs_existente] <= 10  # 10km mínimo entre ENASFs
                pode_alocar = false
                break
            end
        end
        
        if pode_alocar && length(ubs_com_enasf) < length(S_Equipes_ENASF)
            push!(ubs_com_enasf, ubs)
            set_start_value(eq_enasf_criadas[ubs], 1.0)
            set_start_value(tem_ENASF[ubs], 1.0)
        else
            set_start_value(eq_enasf_criadas[ubs], 0.0)
            set_start_value(tem_ENASF[ubs], 0.0)
        end
    end
    
    # 3. ATRIBUIÇÕES ENASF: Cada UBS para ENASF mais próxima
    for i in S_n1
        melhor_enasf = nothing
        menor_distancia = Inf
        
        for j in ubs_com_enasf
            if j in dominio_UBS_Emulti[i] && mt_emulti[i, j] < menor_distancia
                menor_distancia = mt_emulti[i, j]
                melhor_enasf = j
            end
        end
        
        # Setar atribuições
        for j in S_n1
            if j in dominio_UBS_Emulti[i]
                if j == melhor_enasf
                    set_start_value(atrib_ENASF[i, j], 1.0)
                else
                    set_start_value(atrib_ENASF[i, j], 0.0)
                end
            end
        end
    end
    
    println("ENASFs alocadas em $(length(ubs_com_enasf)) UBS")
    println("Warm start ENASF aplicado!")
end



function create_model_alocacao_Emulti_ESF(model::Model, indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Tuple{Model, Indices_modelo_alocacao_ESF_Emulti} 

    S_n1 = indices.S_n1
    S_locais_candidatos_n1 = indices.S_Locais_Candidatos_n1
    S_Equipes_ESF =  indices.S_Equipes_ESF
    S_Equipes_ESB =  indices.S_Equipes_ESB
    S_Equipes_ENASF = indices.S_Equipes_ENASF
    mt_emulti = parameters.S_Matriz_Dist.Matriz_Dist_Emulti

    
    #resultado_equipes = extrair_equipes_alocadas(model)
    esf_vals = value.(model[:eq_ESF_n1])
    enasf_vals = value.(model[:eq_ENASF_n1])
    eqs_ESF_criadas = value.(model[:eq_ESF_criadas])
    eqs_Emulti_criadas = value.(model[:eq_enasf_criadas])

    esb_vals = value.(model[:eq_ESB_n1])
    eqs_ESB_criadas = value.(model[:eq_ESB_criadas])


    S_ESF_reais_abertas = []
    S_UBS_ESF_reais = []

    S_ESB_reais_abertas = []
    S_UBS_ESB_reais = []


    S_Emulti_reais_abertas = []
    S_UBS_Emulti_reais = []

    S_ESF_criadas = []
    S_UBS_ESF_criadas = []

    S_ESB_criadas = []
    S_UBS_ESB_criadas = []


    S_Emulti_criadas = []
    S_UBS_Emulti_criadas = []

    idx_fake_ESF = 1000
    idx_fake_ESB = 1000
    idx_fake_Emulti = 1000

    for eq in S_Equipes_ESF
        for n1 in S_n1
            try
                if esf_vals[eq, n1] > 0
                    push!(S_UBS_ESF_reais, n1)
                    push!(S_ESF_reais_abertas, eq)
                end
            catch e
                # Ignora se a chave não existe
            end
        end
    end
 
    for eq in S_Equipes_ESB
        for n1 in S_n1
            try
                if esb_vals[eq, n1] > 0
                    push!(S_UBS_ESB_reais, n1)
                    push!(S_ESB_reais_abertas, eq)
                end
            catch e
                # Ignora se a chave não existe
            end
        end
    end

    for eq in S_Equipes_ENASF, n1 in S_n1
        if enasf_vals[eq, n1] > 0
            push!(S_UBS_Emulti_reais, n1)
            push!(S_Emulti_reais_abertas, eq)
        end
    end
    
    #ESF criadas por UBS
    for n1 in S_n1
        if eqs_ESF_criadas[n1] > 0
            qntd_eqs_criadas = ceil(eqs_ESF_criadas[n1])
            for _ in 1:Int(qntd_eqs_criadas)
                push!(S_UBS_ESF_criadas, n1)
                push!(S_ESF_criadas, idx_fake_ESF + n1)
                idx_fake_ESF += 1000
            end
        end
    end

    #ESB criadas por UBS
    for n1 in S_n1
        if eqs_ESB_criadas[n1] > 0
            qntd_eqs_criadas = ceil(eqs_ESB_criadas[n1])
            for _ in 1:Int(qntd_eqs_criadas)
                push!(S_UBS_ESB_criadas, n1)
                push!(S_ESB_criadas, idx_fake_ESB + n1)
                idx_fake_ESB += 1000
            end
        end
    end

    #Emulti criadas por UBS
    for n1 in S_n1
        if eqs_Emulti_criadas[n1] > 0
            qntd_eqs_criadas = ceil(eqs_Emulti_criadas[n1])
            for _ in 1:Int(qntd_eqs_criadas)
                push!(S_UBS_Emulti_criadas, n1)
                push!(S_Emulti_criadas, idx_fake_Emulti + n1)
                idx_fake_Emulti += 1000
            end
        end
    end

    indices_aloc = Indices_modelo_alocacao_ESF_Emulti(
        S_UBS_ESF_reais,
        S_ESF_reais_abertas,
        S_UBS_Emulti_reais, 
        S_Emulti_reais_abertas,
        S_UBS_ESF_criadas,
        S_ESF_criadas,
        S_UBS_Emulti_criadas,
        S_Emulti_criadas
    )

    Equipes_ESF = vcat(S_ESF_reais_abertas, S_ESF_criadas)
    S_equipes_ESF_reais = collect(1:length(S_ESF_reais_abertas) )
    S_equipes_ESF_candidatas = collect(length(S_ESF_reais_abertas) + 1: length(S_ESF_reais_abertas) + length(S_ESF_criadas) )
    S_Equipes_ESF = vcat(S_equipes_ESF_reais, S_equipes_ESF_candidatas)

    

    Equipes_ESB = vcat(S_ESB_reais_abertas, S_ESB_criadas)
    S_equipes_ESB_reais = collect(1:length(S_ESB_reais_abertas) )
    S_equipes_ESB_candidatas = collect(length(S_ESB_reais_abertas) + 1: length(S_ESB_reais_abertas) + length(S_ESB_criadas) )
    S_Equipes_ESB = vcat(S_equipes_ESB_reais, S_equipes_ESB_candidatas)


    Equipes_Emulti = vcat(S_Emulti_reais_abertas, S_Emulti_criadas)
    S_equipes_Emulti_reais = collect(1:length(S_Emulti_reais_abertas) )
    S_equipes_Emulti_candidatas = collect(length(S_Emulti_reais_abertas) + 1: length(S_Emulti_reais_abertas) + length(S_Emulti_criadas) )
    S_Equipes_Emulti = vcat(S_equipes_Emulti_reais, S_equipes_Emulti_candidatas)

    # Extrair do model quais foram as ESF Abertas, quantas foram criadas e em qual UBS (variaveis  eq_ESF_n1[eq in S_Equipes_ESF, n1 in S_n1] e eq_ESF_criadas[n1 in S_n1])
    # Extrair do model quais foram as Emulti Abertas, criadas e onde foram alocadas (eq_ENASF_n1[eq in S_Equipes_ENASF, n1 in S_n1] e  eq_enasf_criadas[n1 in S_n1])

    #Modelo terá as variaveis de alocacao 
    model_2 = Model(HiGHS.Optimizer)
    aloc_ESF = @variable(model_2, aloc_ESF[i in S_Equipes_ESF, j in S_Equipes_Emulti], Bin)
    #aloc_ESB = @variable(model_2, aloc_ESB[i in S_Equipes_ESB, j in S_Equipes_Emulti], Bin)


    #Restricoes
    #TODO: Vale a pena ter que alocar todas as equipes de uma mesma UBS numa mesma EMulti ?


    #Toda Equipe ESF e ESB tem que ser alocadas a uma equipe Emulti
    @constraint(model_2, [i in S_Equipes_ESF], sum(aloc_ESF[i,j] for j in S_Equipes_Emulti) == 1)
    #@constraint(model_2, [i in S_Equipes_ESB], sum(aloc_ESB[i,j] for j in S_Equipes_Emulti) == 1)

    #Cada Emulti pode receber até 9 equipes
    @constraint(model_2, [j in S_Equipes_Emulti], sum(aloc_ESF[i,j] for i in S_Equipes_ESF) <= 9)
                                                #+ sum(aloc_ESB[i,j] for i in S_Equipes_ESB) )

    #S_UBS_Emulti_reais, S_UBS_Emulti_criadas
    #Funcao Objetivo - Minimizar a distancia total das equipes!
    @expression(model_2, dist_ESF_Real_Emulti_Real,  sum(mt_emulti[S_UBS_ESF_reais[i], S_UBS_Emulti_reais[j]] * aloc_ESF[S_Equipes_ESF[i], S_Equipes_Emulti[j]] for i in 1:length(S_ESF_reais_abertas), j in 1:length(S_UBS_Emulti_reais)))
    
    
    @expression(model_2, dist_ESF_Candidata_Emulti_Real, sum(mt_emulti[S_UBS_ESF_criadas[i], S_UBS_Emulti_reais[j]] * aloc_ESF[S_equipes_ESF_candidatas[i], S_Equipes_Emulti[j]] 
                                                        for i in 1:length(S_ESF_criadas), j in 1:length(S_UBS_Emulti_reais)))
    
    
    
    #@expression(model_2, dist_ESB_Real_Emulti_Real,  sum(mt_emulti[S_UBS_ESB_reais[i], S_UBS_Emulti[j]] * aloc_ESB[S_Equipes_ESB[i], S_Equipes_Emulti[j]] 
                #for i in 1:length(S_ESB_reais_abertas), j in 1:length(S_UBS_Emulti_reais)))
    
    
    #@expression(model_2, dist_ESB_Candidata_Emulti_Real, sum(mt_emulti[S_UBS_ESB_criadas[i], S_UBS_Emulti[j]] * aloc_ESB[S_equipes_ESB_candidatas[i], S_Equipes_Emulti[j]] 
                   # for i in 1:length(S_ESB_criadas), j in 1:length(S_UBS_Emulti_reais)))


    @objective(model_2, Min, dist_ESF_Real_Emulti_Real + dist_ESF_Candidata_Emulti_Real) #+ dist_ESB_Real_Emulti_Real + dist_ESB_Candidata_Emulti_Real)
    



    return model_2, indices_aloc                                                
    #set_optimizer_attribute(model_2, "primal_feasibility_tolerance", 1e-4)
    #set_optimizer_attribute(model_2, "dual_feasibility_tolerance", 1e-4)
    #set_optimizer_attribute(model_2, "time_limit", 300.0)
    #set_optimizer_attribute(model_2, "mip_rel_gap", 0.05)
    #optimize!(model_2)


end