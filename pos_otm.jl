using JLD2


function load_saved_results(filename="resultados_otimizacao.jld2")
    println("Carregando resultados salvos...")
    data = load(filename)
    return data["results"], data["parameters"], data["mun_data"], data["indices"]
end


# Carregar os dados salvos
function main()

results, parameters, mun_data, indices = load_saved_results()


#O que preciso plotar:
#Mapa de contagem com os fluxos de demanda para S_n1
    #Para isso é necessário:
    atribuicoes = results.atribuicoes
    #plotar pontos de unidades abertas n1
    #pontos de demanda

#Mapa de contagem com os fluxos de demanda para S_n2
#Mapa de contagem com os fluxos de demanda para S_n3

#Fluxo de equipes: Gráficos de barra para poder ser positivo e negativo, por nível 


#Agrupar quantidade de pessoas por ponto de nivel e ver utilização das equipes

#Resumo geral dos custos


end