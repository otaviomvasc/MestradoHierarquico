function create_optimization_model(indices::ModelIndices, parameters::ModelParameters, mun_data::MunicipalityData)::Model
    model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(model, "time_limit", 1500.0)
    set_optimizer_attribute(model, "primal_feasibility_tolerance", 1e-6)
    set_optimizer_attribute(model, "mip_rel_gap", 0.05) 
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

    dominio_atr_n1 = parameters.S_domains.dominio_n1
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

    #TODO: Assim que caminhar com resultados criar o builder de modelos!
    flag_has_2_nivel = length(S_n2) > 0 ? true : false
    flag_has_3_nivel = length(S_n3) > 0 ? true : false



    # Criação das variaveis por nivel de decisão
    aloc_n1 = @variable(model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    fluxo_n1 = @variable(model, X_n1[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d], p in S_pacientes] >= 0)
    var_abr_n1 = @variable(model, Abr_n1[n1 in S_n1], Bin)
    fluxo_eq_n1 = @variable(model, eq_n1[eq in S_equipes, n1 in S_n1])

    if flag_has_2_nivel
        fluxo_n2 = @variable(model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1], p in S_pacientes] >= 0)
        var_abr_n2 = @variable(model, Abr_n2[n2 in S_n2] == 1, Bin)
        fluxo_eq_n2 = @variable(model, eq_n2[eq in S_equipes_n2, n1 in S_n2])
    
    end

    if flag_has_3_nivel
        fluxo_n3 = @variable(model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2], p in S_pacientes] >= 0)
        var_abr_n3 = @variable(model, Abr_n3[n3 in S_n3] == 1, Bin)
        fluxo_eq_n3 = @variable(model, eq_n3[eq in S_equipes_n3, n1 in S_n3])
    end
    
    

    
    #Criação das restrições por nivel
    
    #Toda demanda deve ser atendiaa por uma unidade!
    @constraint(model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) == 1)

    @constraint(model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d], 
        p in S_pacientes], Aloc_[d, n1] * S_Valor_Demanda[d] * porcentagem_populacao[p] == X_n1[d,n1,p])

    #Abertura de Locais Candidatos - A principio apenas no nivel 1!
    @constraint(model, [un in S_locais_candidatos_n1], 
    sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) 
    <= sum(S_Valor_Demanda[:]) * Abr_n1[un])
    
    @constraint(model, [n1 in S_n1], sum(X_n1[d, n1, p] for d in S_Pontos_Demanda, p in S_pacientes if n1 in dominio_atr_n1[d]) <= Cap_n1)


    
    #Restrição do fluxo de equipes!
    #Para nivel 1 com locais candidatos a restrição não pode ter valor das equipes reais!
    @constraint(model, [eq in S_equipes, un in S_locais_candidatos_n1], 
           fluxo_eq_n1[eq,un] == sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])


    @constraint(model, [eq in S_equipes, un in S_instalacoes_reais_n1], 
        S_capacidade_CNES_n1[un, eq] + fluxo_eq_n1[eq,un] == sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])

    

    if flag_has_2_nivel
        @constraint(model, [n1 in S_n1, p in S_pacientes], 
        sum(X_n2[n1, n2, p] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(X_n1[d, n1, p] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) )
        
        #@constraint(model, [n2 in S_n2], sum(X_n2[n1,n2, p] for n1 in S_n1, p in S_pacientes if n2 in dominio_atr_n2[n1]) <= Cap_n2)
        @constraint(model, [eq in S_equipes_n2, un in S_instalacoes_reais_n2], 
        S_capacidade_CNES_n2[un, eq] + fluxo_eq_n2[eq,un] == sum(X_n2[n1, un, p] for n1 in S_n1, p in S_pacientes if un in dominio_atr_n2[n1]) * capacidade_maxima_por_equipe_n2[eq])
    
    
    end


    if flag_has_3_nivel
        @constraint(model, [n2 in S_n2, p in S_pacientes], 
        sum(X_n3[n2, n3, p] for n3 in dominio_atr_n3[n2]) ==  percent_n2_n3 * sum(X_n2[n1, n2, p] for n1 in S_n1 if n2 in dominio_atr_n2[n1]) )

        #@constraint(model, [n3 in S_n3], sum(X_n3[n2, n3, p] for n2 in S_n2, p in S_pacientes if n3 in dominio_atr_n3[n2]) <= Cap_n3)

        @constraint(model, [eq in S_equipes_n3, un in S_instalacoes_reais_n3], 
        S_capacidade_CNES_n3[un, eq] + fluxo_eq_n3[eq,un] == sum(X_n3[n2, un, p] for n2 in S_n2, p in S_pacientes if un in dominio_atr_n3[n2]) * capacidade_maxima_por_equipe_n3[eq])
    end



    #Definicao das F.O's



    @expression(model, custo_logistico_n1,  sum(X_n1[d, un, p] * Matriz_Dist_n1[d, un] * custo_deslocamento for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))
    @expression(model, custo_fixo_novos_n1, sum(Abr_n1[un] * Custo_abertura_n1 for un in S_locais_candidatos_n1))
    @expression(model, custo_fixo_existente_n1, sum(S_custo_fixo_n1 for un1 in S_instalacoes_reais_n1))
    @expression(model, custo_times_novos_n1, sum(fluxo_eq_n1[eq, un] * S_custo_equipe_n1[eq] for eq in S_equipes, un in S_n1))
    @expression(model, custo_variavel_n1, sum(X_n1[d, un, p] * S_custo_variavel_n1[p] for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))


    if flag_has_2_nivel

        @expression(model, custo_logistico_n2,  sum(X_n2[un, un2, p] * Matriz_Dist_n2[un, un2] * custo_deslocamento for un2 in S_n2, un in S_n1, p in S_pacientes if un2 in dominio_atr_n2[un]))
        #@expression(model, custo_fixo_novos_n2, sum(Abr_n2[un] * Custo_abertura_n2 for un in S_locais_candidatos_n2))
        @expression(model, custo_fixo_existente_n2, sum(S_custo_fixo_n2 for un2 in S_instalacoes_reais_n2))
        @expression(model, custo_times_novos_n2, sum(fluxo_eq_n2[eq, un] * S_custo_equipe_n2[eq] for eq in S_equipes_n2, un in S_n2))
        @expression(model, custo_variavel_n2, sum(X_n2[un,un2, p] * S_custo_variavel_n2[p] for un2 in S_n2, un in S_n1, p in S_pacientes if un2 in dominio_atr_n2[un]))
    else
        @expression(model, custo_logistico_n2, 0.0)
        @expression(model, custo_fixo_existente_n2, 0.0)
        @expression(model, custo_times_novos_n2, 0.0)
        @expression(model, custo_variavel_n2, 0.0)
    end

    if flag_has_3_nivel
        @expression(model, custo_logistico_n3,  sum(X_n3[un2, un3, p] * Matriz_Dist_n3[un2, un3] * custo_deslocamento for un2 in S_n2, un3 in S_n3, p in S_pacientes if un3 in dominio_atr_n3[un2]))
        #@expression(model, custo_fixo_novos_n3, sum(Abr_n3[un] * Custo_abertura_n3 for un in S_locais_candidatos_n3))
        @expression(model, custo_fixo_existente_n3, sum(S_custo_fixo_n3 for un3 in S_instalacoes_reais_n3))
        @expression(model, custo_times_novos_n3, sum(fluxo_eq_n3[eq, un] * S_custo_equipe_n3[eq] for eq in S_equipes_n3, un in S_n3))
        @expression(model, custo_variavel_n3, sum(X_n3[un2,un3, p] * S_custo_variavel_n3[p] for un2 in S_n2, un3 in S_n3, p in S_pacientes if un3 in dominio_atr_n3[un2]))
    else
        @expression(model, custo_logistico_n3, 0.0)
        @expression(model, custo_fixo_existente_n3, 0.0)
        @expression(model, custo_times_novos_n3, 0.0)
        @expression(model, custo_variavel_n3, 0.0)
    end


    @expression(model, custo_logistico, custo_logistico_n1 + custo_logistico_n2 + custo_logistico_n3)
    @expression(model, custo_fixo_novo, custo_fixo_novos_n1)
    @expression(model, custo_fixo_existente, custo_fixo_existente_n1 + custo_fixo_existente_n2 + custo_fixo_existente_n3)
    @expression(model, custo_times_novos, custo_times_novos_n1 + custo_times_novos_n2 + custo_times_novos_n3)
    @expression(model, custo_variavel, custo_variavel_n1 + custo_variavel_n2 + custo_variavel_n3)

    @objective(model, Min, custo_logistico + custo_fixo_novo + custo_fixo_existente + custo_times_novos +  custo_variavel)


    #optimize!(model)
    #obj = objective_value(model)
    #print(obj)


    return model
end

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

function print_parcelas_funcao_objetivo(model)
    println("="^60)
    println("PARCELAS DA FUNCAO OBJETIVO")
    println("="^60)
    
    # Parcelas por nível
    println("\nCUSTOS POR NIVEL:")
    println("-"^40)
    
    # Nível 1 (Primário)
    println("\nNIVEL PRIMARIO:")
    println("  • Custo Logistico N1: R\$ " * string(round(value(model[:custo_logistico_n1]), digits=2)))
    println("  • Custo Fixo Novos N1: R\$ " * string(round(value(model[:custo_fixo_novos_n1]), digits=2)))
    println("  • Custo Fixo Existente N1: R\$ " * string(round(value(model[:custo_fixo_existente_n1]), digits=2)))
    println("  • Custo Equipes Novas N1: R\$ " * string(round(value(model[:custo_times_novos_n1]), digits=2)))
    println("  • Custo Variavel N1: R\$ " * string(round(value(model[:custo_variavel_n1]), digits=2)))
    
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
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes, n1 in dominio_atr_n1[d]], var_pop_atendida[d, eq, n1] <= aloc_n1[d, n1] * S_Valor_Demanda[d])
    @constraint(model, [d in S_Pontos_Demanda, eq in S_equipes], sum(var_pop_atendida[d, eq, n1] for n1 in dominio_atr_n1[d]) <= S_Valor_Demanda[d]) #Sei que esta redundante, mas é um teste para nao ter GAP infinito no solver.

    #Abertura de unidades novas:
    @constraint(model, [d in S_Pontos_Demanda, s in dominio_candidatos_n1[d]], 
                         Aloc_[d, s] <= var_abr_n1[s] )

    #Restricao do fluxo de equipes:
    @constraint(model, [eq in S_equipes, un in S_instalacoes_reais_n1], 
    S_capacidade_CNES_n1[un, eq] + fluxo_eq_n1[eq,un] == sum(pop_atendida[d, eq, un] for d in S_Pontos_Demanda if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])


    @constraint(model, [eq in S_equipes, un in S_locais_candidatos_n1], 
        fluxo_eq_n1[eq,un] == sum(pop_atendida[d, eq, un] for d in S_Pontos_Demanda if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])


    #Limitacao de Orcamentos

    #@expression(model, custo_logistico_n1,  sum(X_n1[d, un, p] * Matriz_Dist_n1[d, un] * custo_deslocamento for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))

    @expression(model, custo_fixo_novos_n1, sum(Abr_n1[un] * S_custo_fixo_n1 for un in S_locais_candidatos_n1))
    @expression(model, custo_fixo_existente_n1, sum(S_custo_fixo_n1 for un1 in S_instalacoes_reais_n1))
    @expression(model, custo_times_novos_n1, sum(fluxo_eq_n1[eq, un] * S_custo_equipe_n1[eq] for eq in S_equipes, un in S_n1))
    @expression(model, custo_variavel_n1, sum(pop_atendida[d, eq,  un] * S_custo_variavel_n1[1] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d]))
    @expression(model, custo_total_n1, custo_fixo_novos_n1 +  custo_fixo_existente_n1 + custo_times_novos_n1 + custo_variavel_n1)
    @constraint(model, custo_total_n1 <= 20000000)


    #Fluxo de nivel Secundario!
    @constraint(model, [n1 in S_n1], 
                sum(X_n2[n1, n2] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(pop_atendida[d, eq, n1] 
                        for  eq in S_equipes, d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]))


    #Fluxo de nivel Terciario!
    @constraint(model, [n2 in S_n2], 
            sum(X_n3[n2, n3] for n3 in dominio_atr_n3[n2]) == 
            percent_n2_n3 * sum(X_n2[n1, n2] for n1 in S_n1 if n2 in dominio_atr_n2[n1]))
                    

    #Funcao Objetivo:
    @objective(model, Max, sum(pop_atendida[d, eq, un] * S_IVS[d] for d in S_Pontos_Demanda, eq in S_equipes, un in S_n1 if un in dominio_atr_n1[d] ))



    optimize!(model)
    obj = objective_value(model)
    println(obj)
    println(value(custo_total_n1))

    #Populacao atendida por equipes - Populacao atual
    # Criar um dicionário para armazenar as listas de resultados por equipe
    resultados_por_equipe = Dict{Int, Vector{Tuple{Int, Int, Float64}}}()
    diferencas_por_equipe = Dict{Int, Vector{Tuple{Int, Int, Float64}}}()

    for eq in S_equipes
        resultados_por_equipe[eq] = Vector{Tuple{Int, Int, Float64}}()
        diferencas_por_equipe[eq] = Vector{Tuple{Int, Int, Float64}}()
    end

    for eq in S_equipes, i in indices.S_Pontos_Demanda, j in dominio_atr_n1[i]
        if value(Aloc_[i,j]) == 1
            valor_pop = value(pop_atendida[i, eq, j])
            diferenca = S_Valor_Demanda[i] - valor_pop
            # Salva (i, j, valor_pop) para cada equipe
            push!(resultados_por_equipe[eq], (i, j, valor_pop))
            # Salva (i, j, diferenca) para cada equipe
            push!(diferencas_por_equipe[eq], (i, j, diferenca))
        end
    end

    for eq in S_equipes
        # Soma das diferenças para a equipe
        soma_diferencas = sum(x[3] for x in diferencas_por_equipe[eq])
        # Soma da população atendida para a equipe
        soma_atendida = sum(x[3] for x in resultados_por_equipe[eq])
        # Soma da demanda total para a equipe
        soma_demanda = soma_atendida + soma_diferencas
        # Calcular a porcentagem da população atendida
        porcentagem_atendida = soma_demanda > 0 ? (soma_atendida / soma_demanda) * 100 : 0.0
        println("Equipe: ", eq)
        println("População atendida: ", soma_atendida)
        println("Demanda total: ", soma_demanda)
        println("Porcentagem da população atendida: ", round(porcentagem_atendida, digits=2), "%")
    end


    # Exemplo de como acessar os resultados:
    # for eq in S_equipes
    #     println("Equipe: ", eq)
    #     println("População atendida (i, j, valor): ", resultados_por_equipe[eq])
    #     println("Diferença demanda - atendida (i, j, valor): ", diferencas_por_equipe[eq])
    # end

end