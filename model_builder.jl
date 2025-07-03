using JuMP, HiGHS
using Base: deepcopy

mutable struct HealthcareModelBuilder
    model::Union{Nothing, Model}
    indices::Union{Nothing, Any}
    parameters::Union{Nothing, Any}
    mun_data::Union{Nothing, Any}
    flags::Dict{Symbol, Bool}
    variables::Dict{Symbol, Any}
end

# Define o construtor externo (função) para criar a instância
function CreateHealthcareModelBuilder(parameters::ModelParameters, indices::ModelIndices, mun_data::MunicipalityData)
    builder = HealthcareModelBuilder(nothing, deepcopy(indices), deepcopy(parameters), deepcopy(mun_data), Dict{Symbol, Bool}(), Dict{Symbol, Any}())
    return builder
end

# Métodos de configuração básica
function with_parameters(builder::HealthcareModelBuilder, parameters::ModelParameters)
    builder.parameters = parameters
    return builder
end

function with_indices(builder::HealthcareModelBuilder, indices::ModelIndices)
    builder.indices = indices
    return builder
end

function with_municipality_data(builder::HealthcareModelBuilder, mun_data::MunicipalityData)
    builder.mun_data = mun_data
    return builder
end


function without_candidates_first_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    #new_builder = builder_oficial
    new_builder.indices.S_n1 = new_builder.indices.S_instalacoes_reais_n1
    new_builder.indices.S_Locais_Candidatos_n1 = Vector{Int}()
    new_builder.parameters.S_domains.dominio_n1 = Dict(
            k => [i for i in new_builder.parameters.S_domains.dominio_n1[k] if i in new_builder.indices.S_n1] 
            for k in new_builder.indices.S_Pontos_Demanda)

    new_builder.parameters.S_domains.dominio_n1 = Dict(
                    k => length(new_builder.parameters.S_domains.dominio_n1[k]) > 0 ? 
                        new_builder.parameters.S_domains.dominio_n1[k] : 
                        [k]
                    for k in keys(new_builder.parameters.S_domains.dominio_n1)
                )

    return new_builder
end


function without_candidates_second_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.indices.S_n2 = new_builder.indices.S_instalacoes_reais_n2
    new_builder.indices.S_Locais_Candidatos_n2 = Vector{Int}()
    new_builder.parameters.S_domains.dominio_n2 = Dict(
        k => [i for i in new_builder.parameters.S_domains.dominio_n2[k] if i in new_builder.indices.S_n2]
        for k in keys(new_builder.parameters.S_domains.dominio_n2)
    )
    return new_builder
end


function without_candidates_third_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.indices.S_n3 = new_builder.indices.S_instalacoes_reais_n3
    new_builder.indices.S_Locais_Candidatos_n3 = Vector{Int}()
    new_builder.parameters.S_domains.dominio_n3 = Dict(
        k => [i for i in new_builder.parameters.S_domains.dominio_n3[k] if i in new_builder.indices.S_n3]
        for k in keys(new_builder.parameters.S_domains.dominio_n3)
    )
    
    return new_builder
end


function without_capacity_constraint_first_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_rest_cap_n1 = Vector{Int}()
    return new_builder
end


function without_capacity_constraint_second_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_rest_cap_n2 = Vector{Int}()
    return new_builder
end


function without_capacity_constraint_third_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_rest_cap_n3 = Vector{Int}()
    return new_builder
end


function without_second_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.indices.S_n2 = Vector{Int}()
    new_builder.parameters.S_domains.dominio_level_n2 = Vector{Int}() #TODO: Converter para boolean
    new_builder.indices.S_Locais_Candidatos_n2 = Vector{Int}()
    new_builder.indices.S_instalacoes_reais_n2 = Vector{Int}()
    new_builder.indices.S_equipes_n2 = Vector{Int}()
    new_builder = without_fix_real_facilities_n2(new_builder)
    new_builder = without_candidates_second_level(new_builder)
    new_builder = without_capacity_constraint_second_level(new_builder)
    return new_builder
end


function without_third_level(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.indices.S_n3 = Vector{Int}()
    new_builder.parameters.S_domains.dominio_level_n3 = Vector{Int}() #TODO: Converter para boolean
    new_builder.indices.S_Locais_Candidatos_n3 = Vector{Int}()
    new_builder.indices.S_instalacoes_reais_n3 = Vector{Int}()
    new_builder.indices.S_equipes_n3 = Vector{Int}()
    new_builder = without_fix_real_facilities_n3(new_builder)
    new_builder = without_candidates_third_level(new_builder)
    new_builder = without_capacity_constraint_third_level(new_builder)
    return new_builder
end


function without_fix_real_facilities_n1(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_fixa_inst_reais_n1 = Vector{Int}()
    return new_builder
end


function without_fix_real_facilities_n2(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_fixa_inst_reais_n2 = Vector{Int}()
    return new_builder
end


function without_fix_real_facilities_n3(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_fixa_inst_reais_n3 = Vector{Int}()
    return new_builder
end


function fixa_alocacoes_primarias_reais(builder::HealthcareModelBuilder)
    new_builder = deepcopy(builder)
    new_builder.parameters.S_domains.dominio_n1 = Dict(k => [new_builder.indices.S_atribuicoes_reais_por_demanda[k]] for k in 1:length(new_builder.indices.S_atribuicoes_reais_por_demanda))
    new_builder = without_capacity_constraint_first_level(new_builder)
    return new_builder
end


# Método para construir o modelo final - Depois que tiver pronto passar para outro metodo!
function build(builder::HealthcareModelBuilder)
    S_n1 = builder.indices.S_n1
    S_n2 = builder.indices.S_n2
    S_n3 = builder.indices.S_n3

    S_locais_candidatos_n1 = builder.indices.S_Locais_Candidatos_n1
    S_locais_candidatos_n2 = builder.indices.S_Locais_Candidatos_n2
    S_locais_candidatos_n3 = builder.indices.S_Locais_Candidatos_n3

    S_instalacoes_reais_n1 = builder.indices.S_instalacoes_reais_n1
    S_instalacoes_reais_n2 = builder.indices.S_instalacoes_reais_n2
    S_instalacoes_reais_n3 = builder.indices.S_instalacoes_reais_n3
    S_Pontos_Demanda = builder.indices.S_Pontos_Demanda

    S_equipes = builder.indices.S_equipes_n1
    S_equipes_n2 = builder.indices.S_equipes_n2
    S_equipes_n3 = builder.indices.S_equipes_n3
    S_pacientes =  builder.mun_data.constantes.S_pacientes
    S_Valor_Demanda = builder.mun_data.S_Valor_Demanda
    porcentagem_populacao = builder.mun_data.constantes.porcentagem_populacao



    dominio_atr_n1 = builder.parameters.S_domains.dominio_n1
    dominio_atr_n2 = builder.parameters.S_domains.dominio_n2
    dominio_atr_n3 = builder.parameters.S_domains.dominio_n3

    dominio_nivel_n2 = builder.parameters.S_domains.dominio_level_n2
    dominio_nivel_n3 = builder.parameters.S_domains.dominio_level_n3

    percent_n1_n2 = builder.mun_data.constantes.percent_n1_n2
    percent_n2_n3 = builder.mun_data.constantes.percent_n2_n3


    #Dados e dominio de capacidades
    dominio_cap_n1 = builder.parameters.S_domains.dominio_rest_cap_n1
    dominio_cap_n2 = builder.parameters.S_domains.dominio_rest_cap_n2
    dominio_cap_n3 = builder.parameters.S_domains.dominio_rest_cap_n3

    Cap_n1 = builder.mun_data.constantes.Cap_n1
    Cap_n2 = builder.mun_data.constantes.Cap_n2
    Cap_n3 = builder.mun_data.constantes.Cap_n3


    capacidade_maxima_por_equipe_n1 = builder.parameters.capacidade_maxima_por_equipe_n1
    capacidade_maxima_por_equipe_n2 = builder.parameters.S_eq_por_paciente_n2
    capacidade_maxima_por_equipe_n3 = builder.parameters.S_eq_por_paciente_n3

    S_custo_equipe_n1 = builder.parameters.S_custo_equipe_n1
    S_custo_equipe_n2 = builder.parameters.S_custo_equipe_n2
    S_custo_equipe_n3 = builder.parameters.S_custo_equipe_n3

    S_capacidade_CNES_n1 = builder.parameters.S_capacidade_CNES_n1
    S_capacidade_CNES_n2 = builder.parameters.S_capacidade_CNES_n2
    S_capacidade_CNES_n3 = builder.parameters.S_capacidade_CNES_n3

    Matriz_Dist_n1 = builder.parameters.S_Matriz_Dist.Matriz_Dist_n1
    Matriz_Dist_n2 = builder.parameters.S_Matriz_Dist.Matriz_Dist_n2
    Matriz_Dist_n3 = builder.parameters.S_Matriz_Dist.Matriz_Dist_n3

    custo_deslocamento = builder.mun_data.constantes.custo_transporte  
    Custo_abertura_n1 = builder.mun_data.constantes.custo_abertura_n1
    Custo_abertura_n2 = builder.mun_data.constantes.custo_abertura_n2
    Custo_abertura_n3 = builder.mun_data.constantes.custo_abertura_n3

    S_custo_variavel_n1 = builder.mun_data.constantes.S_custo_variavel_n1
    S_custo_variavel_n2 = builder.mun_data.constantes.S_custo_variavel_n2
    S_custo_variavel_n3 = builder.mun_data.constantes.S_custo_variavel_n3


    S_custo_fixo_n1 = builder.mun_data.constantes.S_custo_fixo_n1
    S_custo_fixo_n2 = builder.mun_data.constantes.S_custo_fixo_n2
    S_custo_fixo_n3 = builder.mun_data.constantes.S_custo_fixo_n3

    dominio_fixa_instalacoes_reais_n1 = builder.parameters.S_domains.dominio_fixa_inst_reais_n1
    dominio_fixa_instalacoes_reais_n2 = builder.parameters.S_domains.dominio_fixa_inst_reais_n2
    dominio_fixa_instalacoes_reais_n3 = builder.parameters.S_domains.dominio_fixa_inst_reais_n3  

    #TODO: Assim que caminhar com resultados criar o builder de modelos!
    flag_has_2_nivel = length(S_n2) > 0 ? true : false
    flag_has_3_nivel = length(S_n3) > 0 & flag_has_2_nivel == true ? true : false


    time_limit = 1500.0
    gap_max = 0.05

    builder.model = Model(HiGHS.Optimizer)
    set_optimizer_attribute(builder.model, "time_limit", time_limit)
    set_optimizer_attribute(builder.model, "primal_feasibility_tolerance", 1e-6)
    set_optimizer_attribute(builder.model, "mip_rel_gap", gap_max)

    # Criação das variaveis por nivel de decisão
    aloc_n1 = @variable(builder.model, Aloc_[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d]], Bin)
    fluxo_n1 = @variable(builder.model, X_n1[d in S_Pontos_Demanda, n1 in dominio_atr_n1[d], p in S_pacientes] >= 0)
    var_abr_n1 = @variable(builder.model, Abr_n1[n1 in S_n1], Bin)
    fluxo_eq_n1 = @variable(builder.model, eq_n1[eq in S_equipes, n1 in S_n1])


    #TODO: Ainda preciso testar como vai funcionar a criação dessa variaveis sem os niveis secundarios e terciarios, Mas fica pra depois!
    fluxo_n2 = @variable(builder.model, X_n2[n1 in S_n1, n2 in dominio_atr_n2[n1], p in S_pacientes] >= 0)
    var_abr_n2 = @variable(builder.model, Abr_n2[n2 in S_n2], Bin)
    fluxo_eq_n2 = @variable(builder.model, eq_n2[eq in S_equipes_n2, n1 in S_n2])
    

    fluxo_n3 = @variable(builder.model, X_n3[n2 in S_n2, n3 in dominio_atr_n3[n2], p in S_pacientes] >= 0)
    var_abr_n3 = @variable(builder.model, Abr_n3[n3 in S_n3], Bin)
    fluxo_eq_n3 = @variable(builder.model, eq_n3[eq in S_equipes_n3, n1 in S_n3])
    #Criação das restrições por nivel
    

    #Restricoes de Fluxo
    #Primario
    @constraint(builder.model, [d in S_Pontos_Demanda], sum(Aloc_[d, n1] for n1 in dominio_atr_n1[d]) == 1)
    @constraint(builder.model, [d in S_Pontos_Demanda, n1 in dominio_atr_n1[d], 
        p in S_pacientes], Aloc_[d, n1] * S_Valor_Demanda[d] * porcentagem_populacao[p] == X_n1[d,n1,p])

    #Secundario
    if flag_has_2_nivel
        @constraint(builder.model, [n1 in S_n1, p in S_pacientes], 
            sum(X_n2[n1, n2, p] for n2 in dominio_atr_n2[n1]) == percent_n1_n2 * sum(X_n1[d, n1, p] for d in S_Pontos_Demanda if n1 in dominio_atr_n1[d]) )
    end

    #Terciario
    if flag_has_3_nivel
        @constraint(builder.model, [n2 in S_n2, p in S_pacientes], 
            sum(X_n3[n2, n3, p] for n3 in dominio_atr_n3[n2]) ==  percent_n2_n3 * sum(X_n2[n1, n2, p] for n1 in S_n1 if n2 in dominio_atr_n2[n1]) )
    end
    
    
    #Fixação das variaveis de abertura das unidades existentes
    for un in dominio_fixa_instalacoes_reais_n1
        @constraint(builder.model, Abr_n1[un] == 1)
    end


    for un in dominio_fixa_instalacoes_reais_n2
        @constraint(builder.model, Abr_n2[un] == 1)
    end


    for un in dominio_fixa_instalacoes_reais_n3
        @constraint(builder.model, Abr_n3[un] == 1)
    end


    #Abertura de Locais Candidatos
    for un in S_locais_candidatos_n1
        @constraint(builder.model, 
        sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) 
        <= sum(S_Valor_Demanda[:]) * Abr_n1[un])

    end

    for un in S_locais_candidatos_n2
        @constraint(builder.model, 
        sum(X_n2[d, un, p] for d in S_n1, p in S_pacientes if un in dominio_atr_n2[d]) 
        <= sum(S_Valor_Demanda[:]) * Abr_n2[un])
    end

    for un in S_locais_candidatos_n3
        @constraint(builder.model, 
        sum(X_n3[d, un, p] for d in S_n2, p in S_pacientes if un in dominio_atr_n3[d]) 
        <= sum(S_Valor_Demanda[:]) * Abr_n3[un])
    end
        

    #Restricoes de Capacidade!
    for n1 in dominio_cap_n1
        @constraint(builder.model, sum(X_n1[d, n1, p] for d in S_Pontos_Demanda, p in S_pacientes if n1 in dominio_atr_n1[d]) <= Cap_n1)
    end

    for n1 in dominio_cap_n2
        @constraint(builder.model, sum(X_n2[d, n1, p] for d in S_Pontos_Demanda, p in S_pacientes if n1 in dominio_atr_n2[d]) <= Cap_n2)
    end

    for n1 in dominio_cap_n3
        @constraint(builder.model, sum(X_n3[d, n1, p] for d in S_Pontos_Demanda, p in S_pacientes if n1 in dominio_atr_n3[d]) <= Cap_n3)
    end



    #Restricoes de Equipes!
    # Nivel primario:
    for un in S_instalacoes_reais_n1
        @constraint(builder.model, [eq in S_equipes], 
            S_capacidade_CNES_n1[un, eq] + fluxo_eq_n1[eq,un] == sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])
    end

    for un in S_locais_candidatos_n1
        @constraint(builder.model, [eq in S_equipes], 
            fluxo_eq_n1[eq,un] == sum(X_n1[d, un, p] for d in S_Pontos_Demanda, p in S_pacientes if un in dominio_atr_n1[d]) * capacidade_maxima_por_equipe_n1[eq])
    
    end


    #Nivel Secundario:    
    for un in S_instalacoes_reais_n2
        @constraint(builder.model, [eq in S_equipes_n2], 
        S_capacidade_CNES_n2[un, eq] + fluxo_eq_n2[eq,un] == sum(X_n2[n1, un, p] for n1 in S_n1, p in S_pacientes if un in dominio_atr_n2[n1]) * capacidade_maxima_por_equipe_n2[eq])
    end

    for un in S_locais_candidatos_n2
        @constraint(builder.model, [eq in S_equipes_n2], 
        fluxo_eq_n2[eq,un] == sum(X_n2[n1, un, p] for n1 in S_n1, p in S_pacientes if un in dominio_atr_n2[n1]) * capacidade_maxima_por_equipe_n2[eq])
    end


    #Nivel Terciario:
    for un in S_instalacoes_reais_n3
        @constraint(builder.model, [eq in S_equipes_n3 ], 
        S_capacidade_CNES_n3[un, eq] + fluxo_eq_n3[eq,un] == sum(X_n3[n2, un, p] for n2 in S_n2, p in S_pacientes if un in dominio_atr_n3[n2]) * capacidade_maxima_por_equipe_n3[eq])
    end

    for un in S_locais_candidatos_n3
        @constraint(builder.model, [eq in S_equipes_n3 ], 
        fluxo_eq_n3[eq,un] == sum(X_n3[n2, un, p] for n2 in S_n2, p in S_pacientes if un in dominio_atr_n3[n2]) * capacidade_maxima_por_equipe_n3[eq])
    end
    
    
        
    
    #Definicao das F.O's
    @expression(builder.model, custo_logistico_n1,  sum(X_n1[d, un, p] * Matriz_Dist_n1[d, un] * custo_deslocamento for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))
    @expression(builder.model, custo_fixo_novos_n1, sum(Abr_n1[un] * Custo_abertura_n1 for un in S_locais_candidatos_n1))
    @expression(builder.model, custo_fixo_existente_n1, sum(S_custo_fixo_n1 for un1 in S_instalacoes_reais_n1))
    @expression(builder.model, custo_times_novos_n1, sum(fluxo_eq_n1[eq, un] * S_custo_equipe_n1[eq] for eq in S_equipes, un in S_n1))
    @expression(builder.model, custo_variavel_n1, sum(X_n1[d, un, p] * S_custo_variavel_n1[p] for d in S_Pontos_Demanda, un in S_n1, p in S_pacientes if un in dominio_atr_n1[d]))


    if flag_has_2_nivel

        @expression(builder.model, custo_logistico_n2,  sum(X_n2[un, un2, p] * Matriz_Dist_n2[un, un2] * custo_deslocamento for un2 in S_n2, un in S_n1, p in S_pacientes if un2 in dominio_atr_n2[un]))
        #@expression(model, custo_fixo_novos_n2, sum(Abr_n2[un] * Custo_abertura_n2 for un in S_locais_candidatos_n2))
        @expression(builder.model, custo_fixo_existente_n2, sum(S_custo_fixo_n2 for un2 in S_instalacoes_reais_n2))
        @expression(builder.model, custo_times_novos_n2, sum(fluxo_eq_n2[eq, un] * S_custo_equipe_n2[eq] for eq in S_equipes_n2, un in S_n2))
        @expression(builder.model, custo_variavel_n2, sum(X_n2[un,un2, p] * S_custo_variavel_n2[p] for un2 in S_n2, un in S_n1, p in S_pacientes if un2 in dominio_atr_n2[un]))
    else
        @expression(builder.model, custo_logistico_n2, 0.0)
        @expression(builder.model, custo_fixo_existente_n2, 0.0)
        @expression(builder.model, custo_times_novos_n2, 0.0)
        @expression(builder.model, custo_variavel_n2, 0.0)
    end

    if flag_has_3_nivel
        @expression(builder.model, custo_logistico_n3,  sum(X_n3[un2, un3, p] * Matriz_Dist_n3[un2, un3] * custo_deslocamento for un2 in S_n2, un3 in S_n3, p in S_pacientes if un3 in dominio_atr_n3[un2]))
        #@expression(model, custo_fixo_novos_n3, sum(Abr_n3[un] * Custo_abertura_n3 for un in S_locais_candidatos_n3))
        @expression(builder.model, custo_fixo_existente_n3, sum(S_custo_fixo_n3 for un3 in S_instalacoes_reais_n3))
        @expression(builder.model, custo_times_novos_n3, sum(fluxo_eq_n3[eq, un] * S_custo_equipe_n3[eq] for eq in S_equipes_n3, un in S_n3))
        @expression(builder.model, custo_variavel_n3, sum(X_n3[un2,un3, p] * S_custo_variavel_n3[p] for un2 in S_n2, un3 in S_n3, p in S_pacientes if un3 in dominio_atr_n3[un2]))
    else
        @expression(builder.model, custo_logistico_n3, 0.0)
        @expression(builder.model, custo_fixo_existente_n3, 0.0)
        @expression(builder.model, custo_times_novos_n3, 0.0)
        @expression(builder.model, custo_variavel_n3, 0.0)
    end


    @expression(builder.model, custo_logistico, custo_logistico_n1 + custo_logistico_n2 + custo_logistico_n3)
    @expression(builder.model, custo_fixo_novo, custo_fixo_novos_n1)
    @expression(builder.model, custo_fixo_existente, custo_fixo_existente_n1 + custo_fixo_existente_n2 + custo_fixo_existente_n3)
    @expression(builder.model, custo_times_novos, custo_times_novos_n1 + custo_times_novos_n2 + custo_times_novos_n3)
    @expression(builder.model, custo_variavel, custo_variavel_n1 + custo_variavel_n2 + custo_variavel_n3)

    @objective(builder.model, Min, custo_logistico + custo_fixo_novo + custo_fixo_existente + custo_times_novos +  custo_variavel)
    
    return builder
end 