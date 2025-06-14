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