using DataFrames, HTTP

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
    #unique_cbo_n1 = sort(unique(mun_data.equipes_n1.profissional_cbo))
    unique_cbo_n2 = sort(unique(mun_data.equipes_n2.profissional_cbo))
    unique_cbo_n3 = sort(unique(mun_data.equipes_n3.profissional_cbo))
    
    #S_equipes_n1 = collect(1:length(unique_cbo_n1))
    S_equipes_n1 = [1, 2, 3] #Equipes de saude da familia,  Equipes Saude Bucal e ENASF !
    S_equipes_n2 = collect(1:length(unique_cbo_n2))
    S_equipes_n3 = collect(1:length(unique_cbo_n3))

    mun_data.equipes_ESF_primario_v2
    mun_data.equipes_ESB_primario_v2
    S_Equipes_ESF = collect(1:length(mun_data.equipes_ESF_primario_v2.CO_EQUIPE))
    S_Equipes_ESB = collect(1:length(mun_data.equipes_ESB_primario_v2.CO_EQUIPE))
    S_Equipes_ENASF = collect(1:length(mun_data.equipes_ENASF_primario_v2.CO_EQUIPE))
 #preciso garantir que a primeira linha desse df está realmente indicando o indice 1 do 

    # Para cada linha do DataFrame mun_data.equipes_ESB_primario_v2, encontre o índice (linha) correspondente do CO_CNES em mun_data.unidades_n1.cnes
    # Cria um dicionário: chave = número da linha em equipes_ESB_primario_v2, valor = índice do CNES em unidades_n1.cnes (ou -1 se não encontrado)
    # Para cada linha do DataFrame, encontre o índice correspondente do CO_CNES em mun_data.unidades_n1.cnes
    S_origem_equipes_ESB = [
        begin
            idx = findfirst(x -> x == row.CO_CNES, mun_data.unidades_n1.cnes)
            idx === nothing ? -1 : idx
        end
        for row in eachrow(mun_data.equipes_ESB_primario_v2)
    ]

    S_origem_equipes_ESF = [
        begin
            idx = findfirst(x -> x == row.CO_CNES, mun_data.unidades_n1.cnes)
            idx === nothing ? -1 : idx
        end
        for row in eachrow(mun_data.equipes_ESF_primario_v2)
    ]

    S_origem_equipes_ENASF = [
        begin
            idx = findfirst(x -> x == row.CO_CNES, mun_data.unidades_n1.cnes)
            idx === nothing ? -1 : idx
        end
        for row in eachrow(mun_data.equipes_ENASF_primario_v2)
    ]

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
        S_atribuicoes_reais_por_demanda,
        S_Equipes_ESF,
        S_Equipes_ESB,
        S_Equipes_ENASF,
        S_origem_equipes_ESB, 
        S_origem_equipes_ESF,
        S_origem_equipes_ENASF
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

function get_real_distance(c1::Tuple{Float64, Float64}, c2::Tuple{Float64, Float64}, data::HealthcareData, mun_data::MunicipalityData)
    # Cria uma chave única para o par de coordenadas (ordem irrelevante)
    key_str = string((c1, c2))
    lat_origem = c1[1]
    long_origem = c1[2]
    lat_destino = c2[1]
    long_destino = c2[2]
    # Tenta ler o JSON com distâncias salvas
    distances = Dict()
    println("Buscando dist na matriz")
    # Verifica se data.matrix_distance existe e busca distância se possível
    if hasproperty(data, :matrix_distance)
        for entry in data.matrix_distance
            try
                if haskey(entry, "origin") && haskey(entry, "destination")
                    origin = entry["origin"]
                    destination = entry["destination"]
                    lat1 = get(origin, "latitude", nothing)
                    lon1 = get(origin, "longitude", nothing)
                    lat2 = get(destination, "latitude", nothing)
                    lon2 = get(destination, "longitude", nothing)
                    if lat1 == lat_origem && lon1 == long_origem && lat2 == lat_destino && lon2 == long_destino
                        if haskey(entry, "distance")
                            return entry["distance"]
                        end
                    end
                    # Também busca pelo caminho reverso
                    if lat1 == lat_destino && lon1 == long_destino && lat2 == lat_origem && lon2 == long_origem
                        if haskey(entry, "distance")
                            return entry["distance"]
                        end
                    end
                end
            catch err
                @warn "Erro ao processar entrada de matrix_distance: $err"
            end
        end
    end

    # Se já temos a distância salva, retorna!
    if haskey(distances, key_str)
        return distances[key_str]
    end
    
    println("Dist nao encontrada! - buscando API")
    # Tenta buscar distância via API (exemplo: OSRM, Google Maps, MapBox etc)
    got_from_api = false
    real_distance_km = nothing
    try
        # Exemplo de chamada a API pública do OSRM (ou substitua pela sua preferida)
        # Cuidado com limites de uso! 
        # No OSRM você pode rodar docker localmente para grandes volumes!
        lon1, lat1 = c1[2], c1[1]
        lon2, lat2 = c2[2], c2[1]
        url = "http://router.project-osrm.org/route/v1/driving/$lon1,$lat1;$lon2,$lat2?overview=false"
        response = HTTP.get(url)
        if response.status == 200
            parsed = JSON.parse(String(response.body))
            if haskey(parsed, "routes") && length(parsed["routes"]) > 0
                real_distance_km = parsed["routes"][1]["distance"] / 1000.0
                got_from_api = true
            end
        end
    catch api_err
        @warn "Erro ao requisitar API de rota real: $api_err"
    end

    # Se conseguiu pela API, salva no JSON e retorna
    if got_from_api && !isnothing(real_distance_km)
        # Atualiza o dicionário e salva JSON
        # Append a new entry, keeping the same dict structure as existing entries in data.matrix_distance
        push!(data.matrix_distance, Dict(
            "origin" => Dict("latitude" => c1[1], "longitude" => c1[2]),
            "destination" => Dict("latitude" => c2[1], "longitude" => c2[2]),
            "distance" => real_distance_km
        ))
        return real_distance_km
    end

    # Fallback: vincenty_distance!
     @warn "Fallback in Distance Matrix! Using Vincent Distance:"
    return vincenty_distance(c1, c2)
end



function real_distance_n1_v2(coords_origem::Vector{Tuple{Float64, Float64}}, coords_destino::Vector{Tuple{Float64, Float64}}, data::HealthcareData, mun_data::MunicipalityData )
    mun_data.Setor_Censitario
    coords_origem = coords_n1
    coords_destino = coords_n1
    #i = 110
    #j = 150
    len_unidades_reais = length(mun_data.unidades_n1.cnes)

    # Cria uma matriz de distâncias inicializada com zeros (ou outra dimensão conforme necessário)
    matriz_distancias = zeros(length(coords_origem), length(coords_destino))

    # Dentro do loop, dentro do if na linha 290, atribui o valor i,j a dist_vd
    # Isso será feito mais abaixo, mas deixamos a matriz pronta aqui.
    #i = 15 j = 900!

    for i in eachindex(coords_origem)
        for j in eachindex(coords_destino)
            println("Buscando distancias para indice $i e $j")
        if i == j || matriz_distancias[i, j] != 0
            #Ja esta salvo como zero!
            continue
        end
        #SE distancia vincenty > 30 km, nem faca o resto das verificacoes!
        dist_vd = vincenty_distance(coords_origem[i], coords_destino[j])
        if dist_vd > 10
            matriz_distancias[i,j] = dist_vd
            println("indice $i e $j foram pela distancia vincent porque sao maiores que 15")
            continue
        end


        if i > len_unidades_reais && j > len_unidades_reais
            #Aqui sao unidades reais e eu posso buscar na matriz!
            setor_origem = replace(mun_data.Setor_Censitario[i - len_unidades_reais], "P" => "")
            setor_destino = replace(mun_data.Setor_Censitario[j - len_unidades_reais], "P" => "")
            println("Buscando dist na matriz")
            # Verifica se data.matrix_distance existe e busca distância se possível
            if hasproperty(data, :matrix_distance)
                for entry in data.matrix_distance
                    try
                        if haskey(entry, "origin") && haskey(entry, "destination")
                            origin = entry["origin"]
                            destination = entry["destination"]
                            setor_origem_m = get(origin, "setor", nothing)
                            setor_destino_m = get(destination, "setor", nothing)

                            if setor_origem_m == setor_origem && setor_destino_m == setor_destino
                                if haskey(entry, "distance")
                                    matriz_distancias[i,j] = entry["distance"]
                                    println("indice $i e $j foram pela distancia JSON")
                                    break # para o loop que percorre data.matrix_distance
                                    continue # volta para o loop principal de j
                                end
                            end
                            # Também busca pelo caminho reverso
                        end
                    catch err
                        @warn "Erro ao processar entrada de matrix_distance: $err"
                    end
                end
            end

        end

        real_distance_km = nothing
        try
            println("indice $i e $j Buscados na API de distancias!")
            lat1 = coords_origem[i][1]
            lon1 = coords_origem[i][2]
            lat2 = coords_destino[j][1]
            lon2 = coords_destino[j][2]
            # Exemplo de chamada a API pública do OSRM (ou substitua pela sua preferida)
            # Cuidado com limites de uso!
            url = "http://router.project-osrm.org/route/v1/driving/$lon1,$lat1;$lon2,$lat2?overview=false"
            response = HTTP.get(url)
            if response.status == 200
                parsed = JSON.parse(String(response.body))
                if haskey(parsed, "routes") && length(parsed["routes"]) > 0
                    real_distance_km = parsed["routes"][1]["distance"] / 1000.0
                    matriz_distancias[i,j] = real_distance_km
                    println("indice $i e $j Encontrados na API de distancias!")
                    continue
                end
            end
        catch api_err
            @warn "Erro ao requisitar API de rota real: $api_err"
        end
        
        println("indice $i e $j Nao caiu em nenhuma condicao e como fallback usar Vincent Distance! CHECK DUDE!")
        matriz_distancias[i,j] = dist_vd

        end  # end for j
    end      # end for i



end


function calculate_distance_matrices(mun_data::MunicipalityData, indices::ModelIndices, data::HealthcareData)::Matriz_Dist
    # Extrair coordenadas

    coords_demanda = mun_data.coordenadas
    
    #TODO: levar isso pro mun_data!
    coords_unidades_reais_n1 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n1)]
    coords_unidades_reais_n2 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n2)]
    coords_unidades_reais_n3 = [(row.latitude, row.longitude) for row in eachrow(mun_data.unidades_n3)]
    
    coords_n1 = vcat(coords_unidades_reais_n1, coords_demanda) 
    coords_n2 = vcat(coords_unidades_reais_n2, coords_demanda)
    coords_n3 = vcat(coords_unidades_reais_n3, coords_demanda)
    
    # Função para obter distância real via JSON e/ou API ou vincenty como fallback

    path_json = "dados_PRONTOS_para_modelo_OTM\\Contagem_matrix_results_full_matrix.json"


    Matriz_Dist_Emulti = [get_real_distance(c1, c2, data, mun_data) for c1 in coords_n1, c2 in coords_n1]
    Matriz_Dist_n1 = [get_real_distance(c1, c2, data, mun_data) for c1 in coords_demanda, c2 in coords_n1]
    Matriz_Dist_n2 = [get_real_distance(c1, c2, data, mun_data) for c1 in coords_n1, c2 in coords_n2]
    Matriz_Dist_n3 = [get_real_distance(c1, c2, data, mun_data) for c1 in coords_n2, c2 in coords_n3]
    
    
    return Matriz_Dist(Matriz_Dist_n1, 
                      Matriz_Dist_n2, 
                      Matriz_Dist_n3, 
                      Matriz_Dist_Emulti)
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
    #O que eu preciso saber?
    #Qual Indice de UBS esta cada equipe 
    # Para cada linha do DataFrame mun_data.equipes_ESB_primario_v2, encontre o índice (linha) correspondente do CO_CNES em mun_data.unidades_n1.cnes

    lista_equipes_n1 = Vector{String}(["MEDICO_FAMILIA"])

    capacidade_n1, custo_n1 = calculate_team_parameters(
        lista_equipes_n1, 
        data.df_necessidades_primario
    )
    #Vetor de equipes!
    
    #matriz_cap_n1 = calculate_equipment_capacity_matrix(
      #  mun_data.unidades_n1,
       # mun_data.equipes_n1,
       # lista_equipes_n1
    #)
    # Cria uma coluna "linha_unidades_n1" que indica a linha em mun_data.unidades_n1 onde o CO_CNES aparece na coluna cnes
    # Ordena o DataFrame equipes_por_cnes pela coluna linha_unidades_n1


    # Cria uma matriz (coluna única) com os valores ordenados da coluna qtd_equipes

    #matriz_cap_n1 = reshape(collect(equipes_por_cnes_sorted.qtd_equipes), :, 1)
    matriz_cap_n1 = reshape(collect(10), :, 1)
    #preciso descobrir qual posicao do vetor e cada CNES!
    
    
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
    

    # Recomenda-se limpar a variável (ou garantir que está criando um novo Dict) antes de reatribuí-la,
    # especialmente se ela já existia e pode ter chaves antigas indesejadas.
    # Aqui, garantimos que estamos criando novos dicionários do zero.

    dominio_atr_n1 = Dict()
    for d in indices.S_Pontos_Demanda
        dominio_atr_n1[d] = [n for n in indices.S_n1 if S_Matriz_Dist.Matriz_Dist_n1[d, n] <= Dist_Maxima_Demanda_N1]
    end

    dominio_atr_n2 = Dict()
    for d in indices.S_n1
        dominio_atr_n2[d] = [n for n in indices.S_n2 if S_Matriz_Dist.Matriz_Dist_n2[d, n] <= Dist_Maxima_n1_n2]
    end

    dominio_atr_n3 = Dict()
    for d in indices.S_n2
        dominio_atr_n3[d] = [n for n in indices.S_n3 if S_Matriz_Dist.Matriz_Dist_n3[d, n] <= Dist_Maxima_n2_n3]
    end
                            
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
            println(length(candidatos_n1_necessarios))
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


        #[k for k in keys(dominio_atr_n3) if length(dominio_atr_n3[k]) == 0]
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
    S_Matriz_Dist = calculate_distance_matrices(mun_data, indices, data)
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
        IVS,
        3000000.0,  # orcamento_maximo - valor padrão
        10.0        # ponderador_Vulnerabilidade - valor padrão
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