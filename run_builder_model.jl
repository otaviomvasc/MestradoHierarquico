using JuMP, HiGHS, JLD2, XLSX
using Base: deepcopy

include("healthcare_model.jl")
include("model_utils.jl")
include("model_builder.jl")
include("optimization_model.jl")


function example_usage()
    # Carregar dados
    data_path = "dados_PRONTOS_para_modelo_OTM"
    municipio = "Contagem"
    
    println("Carregando dados...")
    data = load_healthcare_data(data_path)
    
    println("Filtrando dados para o município: $municipio")
    mun_data = filter_municipality_data(data, municipio)
    
    #TODOs: Deixar mais facil a definicao dos rais criticos!
    mun_data.constantes.raio_maximo_n1 = 2.0
    #mun_data.constantes.raio_maximo_n2 = 20.0
    #mun_data.constantes.raio_maximo_n3 = 50.0

    # Calcular parâmetros do modelo
    println("Calculando parâmetros do modelo...")
    indices, parameters = calculate_model_parameters(mun_data, data)

    # Criar modelo usando o builder
    println("Criando modelo usando o builder...")

    builder_oficial = CreateHealthcareModelBuilder(deepcopy(parameters), deepcopy(indices), deepcopy(mun_data)) |>
    without_second_level |>
    without_third_level |>
    #fixa_alocacoes_primarias_reais |>
    #without_candidates_first_level |>
    without_candidates_second_level |>
    without_candidates_third_level |>

    #without_fix_real_facilities_n1 |>
    #without_fix_real_facilities_n2 |>
    #without_fix_real_facilities_n3 |>

    #without_capacity_constraint_first_level |>
    without_capacity_constraint_second_level |>
    without_capacity_constraint_third_level |>
    build

    println("Resolvendo modelo...")
    optimize!(builder_oficial.model)


    # Fluxos de origem e destino de Pacientes - AIH 
    # Sistemas de saude nao-emergencial (primaria preventiva, diagnostica, condicoes cronicas e agudas e se necessário encaminha para pequenos procedimentos,
    # mas tudo sempre agendado
    # e Hospital - servicos planejados) e emergencial (Pronto atendimento de UPAS e Hospitais, com SAMU)
    # raio critico em funcao do orcamento (Explicou em alguma aula do curso)
    # Dimensionar novas unidades de UBS  
    # Rever conceitos de equidade e acessibilidade
    # Incluir parametros de atratividade
    # Modelo deterministico - Artigo de 2021 - possibilidade de distribuicao de recursos (artigo argentina) na atencao primaria
    # Deslocamento para as atencoes secundarias e terciarias a partir da atencao primaria

    # Capitulo 2: Cenario probabilistico
    # Condicoes cronicas e agudas nos proximos 30 anos
    # Gerando novos cenários de demanda 
    # Impacto das IA's na atencaco secundaria (possibilidade de impacto na atencao secundária)
    # Orcamentos (expansao ou retracao)
    #   

    # TODOS:
        # 


    results = extract_results(builder_oficial.model, builder_oficial.indices)
    version_result = "resultados_otimizacao_builder_cenario_4"
    println("Salvando resultados e dados...")
    save("resultados_otimizacao_$(version_result).jld2", Dict(
        "results" => results,
        "parameters" => parameters,
        "mun_data" => mun_data,
        "indices" => indices
    ))
    print_parcelas_funcao_objetivo(builder_oficial.model)
    gerar_excel_funcao_objetivo(builder_oficial.model, "resultados_custos_n4.xlsx")
    
    return model, results
end

# Executar o exemplo
if abspath(PROGRAM_FILE) == @__FILE__
    model, results = example_usage()
end 