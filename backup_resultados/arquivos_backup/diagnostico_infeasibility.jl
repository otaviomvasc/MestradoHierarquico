using JuMP, HiGHS, JLD2, XLSX
using Base: deepcopy

include("healthcare_model.jl")
include("model_utils.jl")
include("model_builder.jl")
include("optimization_model.jl")

function executar_diagnostico()
    println("=== DIAGNÓSTICO DE INFEASIBILITY ===")
    
    # Carregar dados
    data_path = "dados_PRONTOS_para_modelo_OTM"
    municipio = "Contagem"
    
    println("Carregando dados...")
    data = load_healthcare_data(data_path)
    
    println("Filtrando dados para o município: $municipio")
    mun_data = filter_municipality_data(data, municipio)
    
    # Configurar raios
    mun_data.constantes.raio_maximo_n1 = 2.0
    
    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)
    
    # Executar diagnóstico
    println("\n=== EXECUTANDO DIAGNÓSTICO DETALHADO ===")
    problemas = diagnosticar_infeasibility(nothing, indices, mun_data, parameters)
    
    # Análise adicional
    println("\n=== ANÁLISE ADICIONAL ===")
    
    # Verificar tamanhos dos conjuntos
    println("Tamanhos dos conjuntos:")
    println("- S_Pontos_Demanda: ", length(indices.S_Pontos_Demanda))
    println("- S_n1: ", length(indices.S_n1))
    println("- S_equipes_n1: ", length(indices.S_equipes_n1))
    println("- S_instalacoes_reais_n1: ", length(indices.S_instalacoes_reais_n1))
    println("- S_Locais_Candidatos_n1: ", length(indices.S_Locais_Candidatos_n1))
    
    # Verificar domínios
    println("\nVerificando domínios:")
    domínios_vazios = 0
    domínios_pequenos = 0
    for d in indices.S_Pontos_Demanda
        tamanho_dominio = length(parameters.S_domains.dominio_n1[d])
        if tamanho_dominio == 0
            domínios_vazios += 1
        elseif tamanho_dominio <= 2
            domínios_pequenos += 1
        end
    end
    println("- Domínios vazios: $domínios_vazios")
    println("- Domínios com ≤2 opções: $domínios_pequenos")
    
    # Verificar capacidade vs demanda
    println("\nVerificando capacidade:")
    demanda_total = sum(mun_data.S_Valor_Demanda[d] for d in indices.S_Pontos_Demanda)
    capacidade_total = sum(mun_data.constantes.Cap_n1)
    println("- Demanda total: $demanda_total")
    println("- Capacidade total: $capacidade_total")
    println("- Razão capacidade/demanda: $(capacidade_total/demanda_total)")
    
    # Verificar orçamento
    println("\nVerificando orçamento:")
    custo_minimo = sum(mun_data.constantes.S_custo_fixo_n1)
    orcamento = 2000000
    println("- Custo mínimo: $custo_minimo")
    println("- Orçamento: $orcamento")
    println("- Razão orçamento/custo: $(orcamento/custo_minimo)")
    
    # Resumo dos problemas
    println("\n=== RESUMO DOS PROBLEMAS ===")
    if any(problemas)
        println("❌ PROBLEMAS IDENTIFICADOS:")
        if problemas[1]
            println("- Pontos sem cobertura")
        end
        if problemas[2]
            println("- Capacidade insuficiente")
        end
        if problemas[3]
            println("- Orçamento insuficiente")
        end
        if problemas[4]
            println("- Problemas com equipes")
        end
    else
        println("✅ Nenhum problema crítico identificado")
    end
    
    return problemas, indices, parameters, mun_data
end

# Executar diagnóstico
if abspath(PROGRAM_FILE) == @__FILE__
    problemas, indices, parameters, mun_data = executar_diagnostico()
end
