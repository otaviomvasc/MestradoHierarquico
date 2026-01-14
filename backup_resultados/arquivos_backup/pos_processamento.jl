using JLD2
using CairoMakie
using GeoMakie
using DataFrames
using Statistics
using StatsPlots
using StatsBase
import CairoMakie: scatter!



function plot_flow_map(mun_data, results, parameters, indices)
    fig = Figure(resolution=(2400, 1600))
    ax = GeoAxis(
        fig[1,1],
        title="Fluxo de Pacientes - Nível FULL",
        xlabel="Longitude",
        ylabel="Latitude"
        )
    
    # Extrair coordenadas dos pontos - SEMPRE MANTENDO Locais Reis + Locais Candidatos n1
    demand_coords = mun_data.coordenadas
    demand_lats = [c[1] for c in demand_coords]
    demand_lons = [c[2] for c in demand_coords]

    n1_lats_reais = [mun_data.unidades_n1.latitude[i] for i in indices.S_instalacoes_reais_n1]
    n1_lons_reais = [mun_data.unidades_n1.longitude[i] for i in indices.S_instalacoes_reais_n1]

    n1_lats = vcat(n1_lats_reais,demand_lats)
    n1_lons = vcat(n1_lons_reais,demand_lons)

    n1_lats_candidatos_abertos =  [n1_lats[i] for i in indices.S_Locais_Candidatos_n1 if i in results.unidades_abertas_n1]
    n1_lons_candidatos_abertos =  [n1_lons[i] for i in indices.S_Locais_Candidatos_n1 if i in results.unidades_abertas_n1]

    n2_lats = [mun_data.unidades_n2.latitude[i] for i in indices.S_instalacoes_reais_n2]
    n2_lons = [mun_data.unidades_n2.longitude[i] for i in indices.S_instalacoes_reais_n2]

    n3_lats = [mun_data.unidades_n3.latitude[i] for i in indices.S_instalacoes_reais_n3]
    n3_lons = [mun_data.unidades_n3.longitude[i] for i in indices.S_instalacoes_reais_n3]

    #Plot pontos demanda!
    scatter!(ax, demand_lons, demand_lats,
        color=:gray, alpha=0.5, markersize=5
        )

    # Adicionar índices aos pontos de demanda
    for i in 1:length(demand_lats)
        text!(ax, demand_lons[i], demand_lats[i],
            text="D$(i)",
            align=(:center, :bottom),
            offset=(0, -10),
            fontsize=8
        )
    end

    # Plotar unidades reais primarias e seus índices
    scatter!(ax, n1_lons_reais, n1_lats_reais,
    color=:blue, markersize=10,
    marker=:square,
    label="Unidades Reais Nível 1"
        )

    # Adicionar índices às unidades reais
    for (idx, i) in enumerate(indices.S_instalacoes_reais_n1)
        text!(ax, n1_lons_reais[idx], n1_lats_reais[idx],
            text="R$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end

    # Plotar unidades candidatas primarias abertas e seus índices
    scatter!(ax, n1_lons_candidatos_abertos, n1_lats_candidatos_abertos,
    color=:red, markersize=15,
    marker=:square,
    label="Unidades Candidatas Abertas Nível 1"
        )

    # Adicionar índices às unidades candidatas abertas
    for (idx, i) in enumerate(filter(i -> i in results.unidades_abertas_n1, indices.S_Locais_Candidatos_n1))
        text!(ax, n1_lons_candidatos_abertos[idx], n1_lats_candidatos_abertos[idx],
            text="C$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end

    # Plotar unidades reais primarias e seus índices
    scatter!(ax, n2_lons, n2_lats,
    color=:green, markersize=20,
    marker=:square,
    label="Unidades Reais Nível 2"
    )

    # Adicionar índices às unidades reais
    for (idx, i) in enumerate(indices.S_instalacoes_reais_n2)
        text!(ax, n2_lons[idx], n2_lats[idx],
            text="R$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end

    #Plotar unidades reais tercearias e seus indices
    # Plotar unidades reais primarias e seus índices
    if length(n3_lats) > 0
        scatter!(ax, n3_lons, n3_lats,
        color=:yellow, markersize=20,
        marker=:square,
        label="Unidades Reais Nível 3"
        )

        # Adicionar índices às unidades reais
        for (idx, i) in enumerate(indices.S_instalacoes_reais_n3)
            text!(ax, n3_lons[idx], n3_lats[idx],
                text="R$(i)",
                align=(:center, :bottom),
                offset=(0, -5),
                fontsize=8
            )
        end
    end
    max_flow = maximum(values(results.fluxos))/10
    #end
        # Plotar fluxos
    for ((level,orig,dest,p), flow) in results.fluxos
        if level == 1
            # Origem é ponto de demanda, destino é unidade N1
            orig_coords = (demand_lats[orig], demand_lons[orig])
            dest_coords = (n1_lats[dest], n1_lons[dest])
            if !isnothing(orig_coords) && !isnothing(dest_coords)
                # Plotar linha de fluxo
                lines!([orig_coords[2], dest_coords[2]], [orig_coords[1], dest_coords[1]],
                    color=(:blue, 0.5)
                    #linewidth=max(2 * flow/max_flow, 0.5)
                )
            end
        elseif level == 2
            # Origem é unidade N1, destino é unidade N2
            orig_coords = (n1_lats[orig], n1_lons[orig])
            dest_coords = (n2_lats[dest], n2_lons[dest])
            if !isnothing(orig_coords) && !isnothing(dest_coords)
                # Plotar linha de fluxo
                lines!([orig_coords[2], dest_coords[2]], [orig_coords[1], dest_coords[1]],
                    color=(:yellow, 1)
                   
                )
            end
        else
            # Origem é unidade N2, destino é unidade N3
            orig_coords = (n2_lats[orig], n2_lons[orig])
            dest_coords = (n3_lats[dest], n3_lons[dest])
            if !isnothing(orig_coords) && !isnothing(dest_coords)
                # Plotar linha de fluxo
                lines!([orig_coords[2], dest_coords[2]], [orig_coords[1], dest_coords[1]],
                    color=(:red, 1.5)
                    
                )
            end
        end
    end
    
    #save("fluxo_3_NIVEIS_$(nivel).png", fig)
    save("fluxo_3_NIVEIS_FULL_v2.png", fig)
    return fig
end

function load_saved_results(filename::String)
    println("Carregando resultados salvos...")
    data = load(filename)
    return data["results"], data["parameters"], data["mun_data"], data["indices"]
end

function plot_atribuicoes_primarias(mun_data, results, parameters, indices, versao)
    # Criar figura
    fig = Figure(resolution=(4800, 3200))
    
    # Criar eixo geográfico
    ax = GeoAxis(
        fig[1,1],
        title="Rede de Saúde Otimizada",
        xlabel="Longitude",
        ylabel="Latitude"
    )

    # Extrair coordenadas dos pontos de demanda em ordem
    demand_coords = mun_data.coordenadas
    demand_lats = [c[1] for c in demand_coords]
    demand_lons = [c[2] for c in demand_coords]

    #Concatenando os pontos de unidades reais e unidades candidatas!
    # Plotar unidades REAIS de nível 1
    n1_lats_reais = [mun_data.unidades_n1.latitude[i] for i in indices.S_instalacoes_reais_n1]
    n1_lons_reais = [mun_data.unidades_n1.longitude[i] for i in indices.S_instalacoes_reais_n1]

    n1_lats = vcat(n1_lats_reais,demand_lats)
    n1_lons = vcat(n1_lons_reais,demand_lons)
    
    n1_lats_candidatos_abertos =  [n1_lats[i] for i in indices.S_Locais_Candidatos_n1 if i in results.unidades_abertas_n1]
    n1_lons_candidatos_abertos =  [n1_lons[i] for i in indices.S_Locais_Candidatos_n1 if i in results.unidades_abertas_n1]
    
    # Plotar pontos de demanda e seus índices
    scatter!(ax, demand_lons, demand_lats,
        color=:gray, alpha=0.5, markersize=5,
        label="Pontos de Demanda"
    )
    
    # Adicionar índices aos pontos de demanda
    for i in 1:length(demand_lats)
        text!(ax, demand_lons[i], demand_lats[i],
            text="D$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end
    # Plotar unidades reais e seus índices
    scatter!(ax, n1_lons_reais, n1_lats_reais,
        color=:blue, markersize=10,
        marker=:square,
        label="Unidades Reais Nível 1"
    )
    
    # Adicionar índices às unidades reais
    for (idx, i) in enumerate(indices.S_instalacoes_reais_n1)
        text!(ax, n1_lons_reais[idx], n1_lats_reais[idx],
            text="R$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end
    
    # Plotar unidades candidatas abertas e seus índices
    scatter!(ax, n1_lons_candidatos_abertos, n1_lats_candidatos_abertos,
        color=:red, markersize=10,
        marker=:square,
        label="Unidades Candidatas Abertas Nível 1"
    )
    
    # Adicionar índices às unidades candidatas abertas
    for (idx, i) in enumerate(filter(i -> i in results.unidades_abertas_n1, indices.S_Locais_Candidatos_n1))
        text!(ax, n1_lons_candidatos_abertos[idx], n1_lats_candidatos_abertos[idx],
            text="C$(i)",
            align=(:center, :bottom),
            offset=(0, -5),
            fontsize=8
        )
    end
    
    # Filtrar fluxos do nível atual
    for (orig,dest) in results.atribuicoes
        # Origem é ponto de demanda, destino é unidade N1
        orig_coords = (demand_lats[orig], demand_lons[orig])
        dest_coords = (n1_lats[dest], n1_lons[dest])

        lines!([orig_coords[2], dest_coords[2]], [orig_coords[1], dest_coords[1]],
            color=(:blue, 0.4)
        )
    end

    axislegend(ax, position=:rt)
    nivel = "atr_n1"
    save("fluxo_FULL_35_$(nivel).png", fig)
    return fig
end

function plot_cap_n1(mun_data, results, parameters, indices, versao)
    # Agrupar os fluxos
    df_fluxos = DataFrame(
    level = [k[1] for k in keys(results.fluxos)],
    origem = [k[2] for k in keys(results.fluxos)],
    destino = [k[3] for k in keys(results.fluxos)],
    paciente = [k[4] for k in keys(results.fluxos)],
    fluxo = [v for v in values(results.fluxos)]
    )

    # Agrupar por destino e somar os fluxos
    df_fluxos_agrupados = combine(groupby(df_fluxos, [:destino, :level]), :fluxo => sum => :fluxo_total)
    df_n1 = df_fluxos_agrupados[df_fluxos_agrupados.level .== 1, :]

    print("Unidades abertas acima da capacidade")
    print(size(filter(:fluxo_total => x -> x > 10000, df_n1), 1))





    sort!(df_n1, :fluxo_total, rev=true)  # Ordena o DataFrame em ordem decrescente

    # Criar o gráfico de barras horizontal usando CairoMakie
    fig = Figure(resolution=(1200, 800))  # Aumentei a resolução para melhor visualização
    ax = Axis(fig[1, 1], 
        title="Fluxo Total por Destino (Nível 1)", 
        xlabel="Fluxo Total", 
        ylabel="Destino",
        yticks=(1:nrow(df_n1), string.(df_n1.destino))  # Define os ticks do eixo y
    )

    # Criar o gráfico de barras
    barplot!(ax, 
        1:nrow(df_n1),      # posições das barras
        df_n1.fluxo_total,  # valores das barras
        direction=:x,       # direção horizontal
        color=:blue,        # cor das barras
        alpha=0.7,          # transparência      # largura das barras
    )

    # Ajustar o layout
    ax.xgridvisible = false  # remover grid vertical
    ax.ygridvisible = true   # manter grid horizontal

    # Ajustar fonte dos labels
    ax.yticklabelsize = 12
    ax.xticklabelsize = 12

    # Ajustar margens
    ax.alignmode = Outside(10)  # adicionar margem externa

    # Inverter a ordem do eixo y para que o maior valor fique no topo
    ax.yreversed = true

    # Salvar o gráfico
    save("capacidade.png", fig)
end

function plot_fluxo_equipes_por_cbo(mun_data, results, parameters, indices, versao)
    results.equipes
    #nivel, unidade, equipe!
    df_equipes = DataFrame(
        level = [k[1] for k in keys(results.equipes)],
        unidade = [k[2] for k in keys(results.equipes)],
        equipe = [k[3] for k in keys(results.equipes)],
        fluxo = [v for v in values(results.equipes)]
        )

    unique_cbo_n1 = sort(unique(mun_data.equipes_n1.profissional_cbo))
    unique_cbo_n2 = sort(unique(mun_data.equipes_n2.profissional_cbo))
    unique_cbo_n3 = sort(unique(mun_data.equipes_n3.profissional_cbo))

    df_equipes.cbo = map((eq, lvl) -> begin
        if lvl == 1
            return unique_cbo_n1[eq]
        elseif lvl == 2
            return unique_cbo_n2[eq]
        else
            return unique_cbo_n3[eq]
        end
    end, df_equipes.equipe, df_equipes.level)

        # Agrupar por destino e somar os fluxos
    #Plot apenas para n1 por enquanto!
    uns_plots = vcat(indices.S_instalacoes_reais_n1 , results.unidades_abertas_n1)
    df_eq_n1 = df_equipes[(df_equipes.level .== 1) .& (df_equipes.unidade .∈ Ref(uns_plots)), :]
    df_eqs_n1_fluxo_neg = df_eq_n1[df_eq_n1.fluxo .< 0, :]
    countmap(df_eqs_n1_fluxo_neg.cbo)


    for eq in unique(df_eq_n1.cbo)
        df_plot = df_eq_n1[df_eq_n1.cbo .== eq, :]
        fig = Figure(resolution=(1200, 800))  # Aumentei a resolução para melhor visualização
        ax = Axis(fig[1, 1], 
            title="Fluxo Total por Equipe $(eq)", 
            xlabel="Unidade", 
            ylabel="Fluxo da Equipe $(eq)",
            yticks=(1:nrow(df_plot))  # Define os ticks do eixo y
        )
    
        # Criar o gráfico de barras
        barplot!(ax, 
            1:nrow(df_plot),      # posições das barras
            df_plot.fluxo,  # valores das barras
            direction=:x,       # direção horizontal
            color=:yellow,        # cor das barras
            alpha=0.7,          # transparência      # largura das barras
        )
    
        # Ajustar o layout
        ax.xgridvisible = false  # remover grid vertical
        ax.ygridvisible = true   # manter grid horizontal
    
        # Ajustar fonte dos labels
        ax.yticklabelsize = 12
        ax.xticklabelsize = 12
    
        # Ajustar margens
        ax.alignmode = Outside(10)  # adicionar margem externa
    
        # Inverter a ordem do eixo y para que o maior valor fique no topo
        ax.yreversed = true
    
        # Salvar o gráfico
        save("fluxo_n1_eq_$(eq)_$(versao).png", fig)
    end

end

function generate_all_visualizations()
    println("Carregando resultados...")
    path = "resultados_otimizacao_builder_cenario_3.jld2"
    results, parameters, mun_data, indices = load_saved_results(path)

    println("\nResultados da otimização:")
    println("Status: $(results.status)")
    println("Valor objetivo: $(results.objective_value)")



    println("\nUnidades abertas:")
    println("Nível 1: $(length(results.unidades_abertas_n1)) unidades")
    println("Nível 2: $(length(results.unidades_abertas_n2)) unidades")
    println("Nível 3: $(length(results.unidades_abertas_n3)) unidades")





    println("Gerando mapas da rede hierárquica...")
    rede_primaria =  plot_atribuicoes_primarias(mun_data, results, parameters, indices, "v13")
    #save("rede_saude_primaria.png", rede_primaria)
    rede_secundaria = plot_flow_map(mun_data, results, parameters, indices)	
    save("mapa_flow_cenario_3.png", rede_secundaria)

    println("Gerando Relatórios das Capacidades Utilizadas!")
    plot_cap_n1(mun_data, results, parameters, indices, "v13")
    
    #capacidade_cen_3.png
    println("Gerando Relatórios do Fluxo das Equipes!")
    plot_fluxo_equipes_por_cbo(mun_data, results, parameters, indices, "v13")
    println("Visualizações geradas com sucesso!")

end

# Executar geração de visualizações
if abspath(PROGRAM_FILE) == @__FILE__
    generate_all_visualizations()
end 