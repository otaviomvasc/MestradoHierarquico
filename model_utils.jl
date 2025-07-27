function create_model_indices(mun_data::MunicipalityData)::ModelIndices
    # Calcular quantidades
    qntd_n1_real = nrow(mun_data.unidades_n1)
    qntd_n2_real = nrow(mun_data.unidades_n2)
    qntd_n3_real = nrow(mun_data.unidades_n3)
    qntd_pontos_demanda = length(mun_data.S_Valor_Demanda)
    
    # Criar conjuntos de instalações reais
    S_instalacoes_reais_n1 = collect(1:qntd_n1_real)
    S_instalacoes_reais_n2 = collect(1:qntd_n2_real)
    S_instalacoes_reais_n3 = collect(1:qntd_n3_real)
    
    # Criar conjuntos de locais candidatos
    S_locais_candidatos_n1 = collect((qntd_n1_real + 1):(qntd_pontos_demanda + qntd_n1_real))
    S_locais_candidatos_n2 = collect((qntd_n2_real + 1):(qntd_pontos_demanda + qntd_n2_real))
    S_locais_candidatos_n3 = collect((qntd_n3_real + 1):(qntd_pontos_demanda + qntd_n3_real))

    #Definicao de qual indice atende qual ponto de demanda!
    S_atribuicoes_reais_por_demanda  = find_cnes_line_numbers(mun_data.unidades_n1, mun_data.S_cnes_primario_referencia_real)
    
    # Criar conjuntos finais
    S_n1 = vcat(S_instalacoes_reais_n1, S_locais_candidatos_n1)
    S_n2 = vcat(S_instalacoes_reais_n2, S_locais_candidatos_n2)
    S_n3 = vcat(S_instalacoes_reais_n3, S_locais_candidatos_n3)
    
    # Criar conjuntos de equipes
    #TOOD: Salvar esse dado tambem!
    unique_cbo_n1 = sort(unique(mun_data.equipes_n1.profissional_cbo))
    unique_cbo_n2 = sort(unique(mun_data.equipes_n2.profissional_cbo))
    unique_cbo_n3 = sort(unique(mun_data.equipes_n3.profissional_cbo))
    
    S_equipes_n1 = collect(1:length(unique_cbo_n1))
    S_equipes_n2 = collect(1:length(unique_cbo_n2))
    S_equipes_n3 = collect(1:length(unique_cbo_n3))
    
    # Indices de pontos de demanda
    S_pontos_demanda = collect(1:qntd_pontos_demanda)

    return ModelIndices(
        S_n1,
        S_n2,
        S_n3,
        S_pontos_demanda,
        S_equipes_n1,
        S_equipes_n2,
        S_equipes_n3,
        S_locais_candidatos_n1,
        S_locais_candidatos_n2,
        S_locais_candidatos_n3,
        S_instalacoes_reais_n1,
        S_instalacoes_reais_n2,
        S_instalacoes_reais_n3, 
        S_atribuicoes_reais_por_demanda
    )
end

function vincenty_distance(p1::Tuple{<:Real,<:Real}, p2::Tuple{<:Real,<:Real})
    # Constants for WGS-84 ellipsoid
    a = 6378137.0  # semi-major axis in meters
    f = 1/298.257223563  # flattening
    b = a * (1 - f)  # semi-minor axis
    
    # Convert to radians
    lat1, lon1 = deg2rad(p1[1]), deg2rad(p1[2])
    lat2, lon2 = deg2rad(p2[1]), deg2rad(p2[2])
    
    # Calculate parameters
    L = lon2 - lon1
    U1 = atan((1-f) * tan(lat1))
    U2 = atan((1-f) * tan(lat2))
    sinU1 = sin(U1)
    cosU1 = cos(U1)
    sinU2 = sin(U2)
    cosU2 = cos(U2)
    
    # Initial values
    lambda = L
    sinSigma = 0.0
    cosSigma = 0.0
    sigma = 0.0
    sinAlpha = 0.0
    cosSquareAlpha = 0.0
    cos2SigmaM = 0.0
    
    # Check if points are identical or antipodal
    if (lat1 == lat2 && lon1 == lon2)
        return 0.0
    end
    
    iterLimit = 100
    
    # Iterative calculations
    for _ in 1:iterLimit
        sinLambda = sin(lambda)
        cosLambda = cos(lambda)
        sinSigma = sqrt((cosU2*sinLambda)^2 + (cosU1*sinU2-sinU1*cosU2*cosLambda)^2)
        cosSigma = sinU1*sinU2 + cosU1*cosU2*cosLambda
        
        # If points are antipodal (sinSigma ≈ 0 and cosSigma ≈ -1)
        if sinSigma < 1e-12 && abs(cosSigma + 1) < 1e-12
            return π * b / 1000.0 * 1.25  # Return half the Earth's circumference in km
        end
        
        sigma = atan(sinSigma, cosSigma)
        sinAlpha = cosU1*cosU2*sinLambda/max(sinSigma, 1e-12)  # Avoid division by zero
        cosSquareAlpha = 1 - sinAlpha^2
        
        # Handle special case where points are on the equator
        if abs(cosSquareAlpha) < 1e-12
            cos2SigmaM = 0.0
        else
            cos2SigmaM = cosSigma - 2*sinU1*sinU2/cosSquareAlpha
        end
        
        C = f/16*cosSquareAlpha*(4+f*(4-3*cosSquareAlpha))
        lambdaN = L + (1-C)*f*sinAlpha*(sigma + C*sinSigma*(cos2SigmaM + C*cosSigma*(-1+2*cos2SigmaM^2)))
        
        # Break if converged
        if abs(lambdaN - lambda) < 1e-12
            lambda = lambdaN
            break
        end
        lambda = lambdaN
    end
    
    # Calculate final parameters
    uSquare = cosSquareAlpha * (a^2 - b^2) / b^2
    A = 1 + uSquare/16384*(4096+uSquare*(-768+uSquare*(320-175*uSquare)))
    B = uSquare/1024 * (256+uSquare*(-128+uSquare*(74-47*uSquare)))
    
    # Handle special case where points are on the equator
    if abs(cosSquareAlpha) < 1e-12
        cos2SigmaM = 0.0
    else
        cos2SigmaM = cosSigma - 2*sinU1*sinU2/cosSquareAlpha
    end
    
    deltaSigma = B*sinSigma*(cos2SigmaM + B/4*(cosSigma*(-1+2*cos2SigmaM^2) - B/6*cos2SigmaM*(-3+4*sinSigma^2)*(-3+4*cos2SigmaM^2)))
    
    # Calculate distance in kilometers
    return ((b * A * (sigma - deltaSigma)) / 1000.0) # Convert to kilometers
end


function calculate_distance_matrices(mun_data::MunicipalityData, indices::ModelIndices)::Matriz_Dist
    # Extrair coordenadas

    coords_demanda = mun_data.coordenadas
    
    #TODO: levar isso pro mun_data!
    coords_unidades_reais_n1 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n1)]
    coords_unidades_reais_n2 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n2)]
    coords_unidades_reais_n3 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n3)]
    
    coords_n1 = vcat(coords_unidades_reais_n1, coords_demanda)
    coords_n2 = vcat(coords_unidades_reais_n2, coords_demanda)
    coords_n3 = vcat(coords_unidades_reais_n3, coords_demanda)
    

    Matriz_Dist_n1 = [vincenty_distance(c1, c2) for c1 in coords_demanda, c2 in coords_n1]
    Matriz_Dist_n2 = [vincenty_distance(c1, c2) for c1 in coords_n1, c2 in coords_n2]
    Matriz_Dist_n3 = [vincenty_distance(c1, c2) for c1 in coords_n2, c2 in coords_n3]
    
    
    return Matriz_Dist(Matriz_Dist_n1, 
                      Matriz_Dist_n2, 
                      Matriz_Dist_n3)
end


function calculate_equipment_capacity_matrix(unidades::DataFrame, equipes::DataFrame, lista_equipes::Vector{String})::Matrix{Float64}
    qntd_equipes = length(lista_equipes)
    qntd_unidades = nrow(unidades)
    
    # Inicializa matriz de capacidades
    capacidade_matrix = zeros(qntd_unidades, qntd_equipes)
    
    # Para cada unidade
    for (i, cnes) in enumerate(unidades.cnes)
        # Para cada tipo de equipe
        for (j, eq) in enumerate(lista_equipes)
            # Filtra equipes desta unidade
            v = filter(row -> row.cnes == cnes && row.profissional_cbo == eq, equipes)
            if nrow(v) == 1
                capacidade_matrix[i, j] = v[!, "qntd_eqs"][1]
            end
        end
    end
    
    return capacidade_matrix
end


function calculate_team_parameters(lista_equipes::Vector{String}, df_necessidades::DataFrame)::Tuple{Vector{Float64}, Vector{Float64}}
    # Valores padrão para especialidades não encontradas
    v_outros = 1/10000
    v_outros_custo = 11000/30
    
    # Pegar valores para "Outras especialidades" se existir
    v_outras = filter(row -> row.Especialidade == "Outras especialidades", df_necessidades)
    if nrow(v_outras) > 0
        v_outros = v_outras[!, "Razao"][1]
        v_outros_custo = v_outras[!, "Custo"][1]
    end
    
    capacidades = Float64[]
    custos = Float64[]
    
    # Para cada tipo de equipe
    for eq in lista_equipes
        v = filter(row -> row.Especialidade == eq, df_necessidades)
        if nrow(v) > 0
            push!(capacidades, v[!, "Razao"][1])
            push!(custos, v[!, "Custo"][1])
        else
            push!(capacidades, v_outros)
            push!(custos, v_outros_custo)
        end
    end
    
    return capacidades, custos
end


function calculate_equipment_parameters(mun_data::MunicipalityData, data::HealthcareData)::Tuple{
        Vector{Float64}, Vector{Float64},  # capacidade_n1, custo_n1
        Vector{Float64}, Vector{Float64},  # capacidade_n2, custo_n2
        Vector{Float64}, Vector{Float64},  # capacidade_n3, custo_n3
        Matrix{Float64}, Matrix{Float64}, Matrix{Float64}  # matriz_cap_n1, matriz_cap_n2, matriz_cap_n3
    }
    
    # Nível 1 (Primário)
    lista_equipes_n1 = Vector{String}(unique(mun_data.equipes_n1.profissional_cbo))
    capacidade_n1, custo_n1 = calculate_team_parameters(
        lista_equipes_n1, 
        data.df_necessidades_primario
    )
    matriz_cap_n1 = calculate_equipment_capacity_matrix(
        mun_data.unidades_n1,
        mun_data.equipes_n1,
        lista_equipes_n1
    )
    
    # Nível 2 (Secundário)
    lista_equipes_n2 = Vector{String}(unique(mun_data.equipes_n2.profissional_cbo))
    capacidade_n2, custo_n2 = calculate_team_parameters(
        lista_equipes_n2, 
        data.df_necessidades_sec_ter
    )
    matriz_cap_n2 = calculate_equipment_capacity_matrix(
        mun_data.unidades_n2,
        mun_data.equipes_n2,
        lista_equipes_n2
    )
    
    # Nível 3 (Terciário)
    lista_equipes_n3 = Vector{String}(unique(mun_data.equipes_n3.profissional_cbo))
    capacidade_n3, custo_n3 = calculate_team_parameters(
        lista_equipes_n3, 
        data.df_necessidades_sec_ter
    )
    matriz_cap_n3 = calculate_equipment_capacity_matrix(
        mun_data.unidades_n3,
        mun_data.equipes_n3,
        lista_equipes_n3
    )
    
    return capacidade_n1, custo_n1, 
           capacidade_n2, custo_n2, 
           capacidade_n3, custo_n3,
           matriz_cap_n1, matriz_cap_n2, matriz_cap_n3
end


function calculate_domains_capacity_constrant(indices::ModelIndices)::Tuple{Vector{Int64},Vector{Int64}, Vector{Int64}}
    S_dominio_cap_n1 = indices.S_n1
    S_dominio_cap_n2 = indices.S_n2
    S_dominio_cap_n3 = indices.S_n3

    return (S_dominio_cap_n1, S_dominio_cap_n2, S_dominio_cap_n3)
end



function calculate_flow_patients_domain(mun_data::MunicipalityData, data::HealthcareData, S_Matriz_Dist::Matriz_Dist, indices::ModelIndices)

    Dist_Maxima_Demanda_N1 = mun_data.constantes.raio_maximo_n1
    Dist_Maxima_n1_n2 = mun_data.constantes.raio_maximo_n2
    Dist_Maxima_n2_n3 = mun_data.constantes.raio_maximo_n3


    dominio_atr_n1 = Dict(d => [n for n in indices.S_n1 if S_Matriz_Dist.Matriz_Dist_n1[d,n] <= Dist_Maxima_Demanda_N1] 
                         for d in indices.S_Pontos_Demanda)

    dominio_atr_n2 = Dict(d => [n for n in indices.S_n2 if S_Matriz_Dist.Matriz_Dist_n2[d,n] <= Dist_Maxima_n1_n2] 
                         for d in indices.S_n1)

    dominio_atr_n3 = Dict(d => [n for n in indices.S_n3 if S_Matriz_Dist.Matriz_Dist_n3[d,n] <= Dist_Maxima_n2_n3] 
                         for d in indices.S_n2)
    
                            
    return dominio_atr_n1, dominio_atr_n2, dominio_atr_n3

end


function calculate_domains_second_and_third_level(indices::ModelIndices)::Tuple{Vector{Int64}, Vector{Int64}}
    S_dominio_level_n2 = indices.S_n2
    S_dominio_level_n3 = indices.S_n3

    return (S_dominio_level_n2, S_dominio_level_n3)

end


function calculate_domain_fix_instalacoes_reais(indices::ModelIndices)::Tuple{Vector{Int64},Vector{Int64}, Vector{Int64}}
    dominio_fixa_inst_reais_n1 = indices.S_instalacoes_reais_n1
    dominio_fixa_inst_reais_n2 = indices.S_instalacoes_reais_n2
    dominio_fixa_inst_reais_n3 = indices.S_instalacoes_reais_n3

    return (dominio_fixa_inst_reais_n1, dominio_fixa_inst_reais_n2, dominio_fixa_inst_reais_n3)
end


function calculate_domains(mun_data::MunicipalityData, data::HealthcareData, S_Matriz_Dist::Matriz_Dist, indices::ModelIndices, reduz_instalacoes_candidatas::Bool)::Domains
    # Constantes de distância máxima
    dominio_atr_n1, dominio_atr_n2, dominio_atr_n3 = calculate_flow_patients_domain(mun_data::MunicipalityData, data::HealthcareData, S_Matriz_Dist::Matriz_Dist, indices::ModelIndices)
    S_dominio_cap_n1, S_dominio_cap_n2, S_dominio_cap_n3 = calculate_domains_capacity_constrant(indices::ModelIndices)
    S_dominio_level_n2, S_dominio_level_n3 = calculate_domains_second_and_third_level(indices::ModelIndices)
    dominio_fixa_inst_reais_n1, dominio_fixa_inst_reais_n2, dominio_fixa_inst_reais_n3 = calculate_domain_fix_instalacoes_reais(indices::ModelIndices)

    if reduz_instalacoes_candidatas == true

        cs_atendidos_somente_candidatos = [d for d in keys(dominio_atr_n1) if length([k for k in dominio_atr_n1[d] if k in indices.S_instalacoes_reais_n1]) == 0]
        candidatos_n1_necessarios = []
        for cs in cs_atendidos_somente_candidatos
            candidatos_n1_necessarios = vcat(candidatos_n1_necessarios, dominio_atr_n1[cs] )
        end

        indices.S_Locais_Candidatos_n1 = unique(candidatos_n1_necessarios)
        indices.S_n1 = vcat(indices.S_instalacoes_reais_n1, indices.S_Locais_Candidatos_n1)

        cs_atendidos_somente_candidatos_n2 = [d for d in keys(dominio_atr_n2) if length([ k for k in dominio_atr_n2[d] if k in indices.S_instalacoes_reais_n2]) == 0]
        candidatos_n2_necessarios = []
        for cs in cs_atendidos_somente_candidatos_n2
            candidatos_n2_necessarios = vcat(candidatos_n2_necessarios, dominio_atr_n2[cs])
        end

        indices.S_Locais_Candidatos_n2 = unique(candidatos_n2_necessarios)
        indices.S_n2 = vcat(indices.S_instalacoes_reais_n2, indices.S_Locais_Candidatos_n2)



        cs_atendidos_somente_candidatos_n3 = [d for d in keys(dominio_atr_n3) if length([ k for k in dominio_atr_n3[d] if k in indices.S_instalacoes_reais_n3]) == 0]
        candidatos_n3_necessarios = []
        for cs in cs_atendidos_somente_candidatos_n3
            candidatos_n3_necessarios = vcat(candidatos_n3_necessarios, dominio_atr_n3[cs])
        end

        indices.S_Locais_Candidatos_n3 = unique(candidatos_n3_necessarios)
        indices.S_n3 = vcat(indices.S_instalacoes_reais_n3, indices.S_Locais_Candidatos_n3)


        dominio_atr_n1, dominio_atr_n2, dominio_atr_n3 = calculate_flow_patients_domain(mun_data::MunicipalityData, data::HealthcareData, S_Matriz_Dist::Matriz_Dist, indices::ModelIndices)



    end



    return Domains(dominio_atr_n1, 
                  dominio_atr_n2, 
                  dominio_atr_n3, 
                  S_dominio_cap_n1, 
                  S_dominio_cap_n2, 
                  S_dominio_cap_n3,
                  S_dominio_level_n2,
                  S_dominio_level_n3,
                  dominio_fixa_inst_reais_n1,
                  dominio_fixa_inst_reais_n2,
                  dominio_fixa_inst_reais_n3,
                  )

end


function create_model_parameters(mun_data::MunicipalityData, data::HealthcareData, indices::ModelIndices)::ModelParameters
    # Calcular matrizes de distância
    S_Matriz_Dist = calculate_distance_matrices(mun_data, indices)
    dominios_model = calculate_domains(mun_data, data, S_Matriz_Dist, indices, true)
    # Calcular parâmetros das equipes
    capacidade_n1, custo_n1, 
    capacidade_n2, custo_n2, 
    capacidade_n3, custo_n3,
    matriz_cap_n1, matriz_cap_n2, matriz_cap_n3 = calculate_equipment_parameters(mun_data, data)
    IVS = mun_data.IVS

    return ModelParameters(
        capacidade_n1,
        custo_n1,
        capacidade_n2,
        custo_n2,
        capacidade_n3,
        custo_n3,
        matriz_cap_n1,
        matriz_cap_n2,
        matriz_cap_n3,
        S_Matriz_Dist,
        dominios_model, 
        IVS
    )
end


function find_cnes_line_numbers(df_und::DataFrame, S_cnes::Vector{Int64})::Vector{Int64}
    # Create a vector to store the line numbers
    line_numbers = Int64[]
    #(mun_data.unidades_n1, mun_data.S_cnes_primario_referencia_real 
    #S_cnes = mun_data.S_cnes_primario_referencia_real

    for cnes in S_cnes
        # Find the first occurrence of this CNES in unidades_n1.cnes
        line_number = findfirst(x -> x == cnes, df_und.cnes)
        if line_number !== nothing
            push!(line_numbers, line_number)
        else
            push!(line_numbers, -1)  # -1 indicates CNES not found
        end
    end
    
    return line_numbers
end 