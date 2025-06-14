using Pkg
using JuMP, HiGHS, JLD2

# Adicionar pacotes necessários se não estiverem instalados
for pkg in ["JuMP", "HiGHS", "DataFrames", "XLSX", "CSV", "Distances", "JLD2"]
    try
        @eval using $(Symbol(pkg))
    catch
        Pkg.add(pkg)
        @eval using $(Symbol(pkg))
    end
end
include("healthcare_model.jl")
include("model_utils.jl")
include("optimization_model.jl")

function main()
    # Configurar logging
    println("Iniciando otimização do sistema de saúde")
    
    try
        # Definir caminhos e parâmetros
        data_path = "dados_PRONTOS_para_modelo_OTM"
        municipio = "Contagem"
        
        # Carregar dados
        println("Carregando dados...")
        data = load_healthcare_data(data_path)
        
        # Filtrar dados do município
        println("Filtrando dados para o município: $municipio")
        mun_data = filter_municipality_data(data, municipio)
        
        # Calcular parâmetros do modelo
        println("Calculando parâmetros do modelo...")
        indices, parameters = calculate_model_parameters(mun_data, data)
        
        # Criar modelo de otimização
        println("Criando modelo de otimização...")
        model = create_optimization_model(indices, parameters, mun_data)
        
        # Resolver modelo
        println("Resolvendo modelo...")
        optimize!(model)
        
        # Extrair e processar resultados
        println("Processando resultados...")
        results = extract_results(model, indices)

        # Salvar resultados e dados para pós-processamento
        println("Salvando resultados e dados...")
        save("resultados_otimizacao_Contagem_End.jld2", Dict(
            "results" => results,
            "parameters" => parameters,
            "mun_data" => mun_data,
            "indices" => indices
        ))
        
        # Imprimir resultados
        println("\nResultados da otimização:")
        println("Status: $(results.status)")
        println("Valor objetivo: $(results.objective_value)")
        println("\nUnidades abertas:")
        println("Nível 1: $(length(results.unidades_abertas_n1)) unidades")
        println("Nível 2: $(length(results.unidades_abertas_n2)) unidades")
        println("Nível 3: $(length(results.unidades_abertas_n3)) unidades")
        
        return model, results
        
    catch e
        println("Erro durante a execução:")
        println(e)
        rethrow(e)
    end
end

function load_saved_results(filename="resultados_otimizacao.jld2")
    println("Carregando resultados salvos...")
    data = load(filename)
    return data["results"], data["parameters"], data["mun_data"], data["indices"]
end

# Executar o programa
if abspath(PROGRAM_FILE) == @__FILE__
    model, results = main()
end 