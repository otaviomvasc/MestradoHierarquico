# %%
import os
import geopandas as gpd
import pandas as pd
import matplotlib.pyplot as plt
import folium
from folium.plugins import (
    MarkerCluster,
    MeasureControl,
    Draw,
    OverlappingMarkerSpiderfier,
)
import locale

locale.setlocale(locale.LC_ALL, "")
from shapely import Point
from tqdm import tqdm
import argparse
from geopy.distance import geodesic
import importlib
import sys
import importlib


pd.set_option("display.max_columns", 200)

# %%


def plota_mapa_vulnerabilidade(path_resultado, indice_ponderado=1):
    path_dados_cs = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\pos_otm\setores_ligth_processado.gpkg"
    path_resultado_ord = path_resultado
    path_dados_brutos = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Definicao_MDC\Dados_BRUTOS_CONTAGEM_FIM.xlsx"

    df_cs = gpd.read_file(path_dados_cs)
    id_contagem = 311860
    df_cs_contagem = df_cs[df_cs.CO_MUNICIPIO == 311860]
    df_cs_contagem.id_setor = df_cs_contagem.id_setor.astype(int)
    df_result_TP = pd.read_excel(path_resultado_ord)
    df_result_TP.rename(
        columns={
            i: f"{i}_ponderado"
            for i in [
                "V00008",
                "V00052",
                "V00064",
                "V00111",
                "V00201",
                "V00238",
                "V00314",
                "V00401",
                "V00901",
                "V01041",
                "VPB01",
                "VPB02",
                "VPB03",
                "VPB04",
                "VPB05",
                "VPB06",
                "VPB07",
            ]
        },
        inplace=True,
    )
    df_dados_base_contagem = pd.read_excel(path_dados_brutos)
    df_merge_aux = df_dados_base_contagem.merge(
        df_result_TP, on="CD_setor", how="inner"
    )
    df_end = df_merge_aux.merge(
        df_cs_contagem, how="left", right_on="id_setor", left_on="CD_setor"
    )
    col_result_TP = "Score_TOPSIS"
    col_rank_TP = "Ranking"

    cols_indices_to_plot = [
        "V00008",
        "V00052",
        "V00064",
        "V00111",
        "V00201",
        "V00238",
        "V00314",
        "V00401",
        "V00901",
        "V01041",
        "V01006",
        "VPB01",
        "VPB02",
        "VPB03",
        "VPB04",
        "VPB05",
        "VPB06",
        "VPB07",
        col_result_TP,
        col_rank_TP,
    ]
    # df_end[col_result_TP] = df_end[col_result_TP] * 1000
    cols_geo = "geometry"
    lat_long_contagem = (-19.9321, -44.0539)
    resultado = gpd.GeoDataFrame(df_end, geometry="geometry")
    map = folium.Map(
        location=[lat_long_contagem[0], lat_long_contagem[1]],
        tiles="cartodbpositron",
        control_scale=True,
        prefer_canvas=True,
        zoom_start=11,
    )

    # Configurar o índice do GeoDataFrame para o Choropleth
    resultado_choropleth = resultado.copy()
    resultado_choropleth = resultado_choropleth.reset_index()
    resultado_choropleth["id"] = resultado_choropleth.index

    # Calcular bins personalizados para melhor distribuição das cores
    min_val = resultado_choropleth[col_result_TP].min()
    max_val = resultado_choropleth[col_result_TP].max()
    print(f"Valor mínimo: {min_val:.4f}")
    print(f"Valor máximo: {max_val:.4f}")

    # Criar bins personalizados (5 categorias)
    bins = (
        [min_val]
        + list(
            resultado_choropleth[col_result_TP].quantile(
                [
                    0.05,
                    0.1,
                    0.15,
                    0.2,
                    0.25,
                    0.30,
                    0.35,
                    0.4,
                    0.45,
                    0.5,
                    0.55,
                    0.6,
                    0.65,
                    0.7,
                    0.75,
                    0.8,
                    0.85,
                    0.9,
                    0.95,
                ]
            )
        )
        + [max_val]
    )
    bins = sorted(list(set(bins)))  # Remove duplicatas e ordena

    folium.Choropleth(
        geo_data=resultado_choropleth,
        name=col_result_TP,
        data=resultado_choropleth,
        columns=["id", col_result_TP],
        key_on="feature.id",
        fill_color="Reds",  # Mudando para vermelho para maior contraste
        fill_opacity=0.9,  # Aumentando opacidade
        line_opacity=0.7,  # Aumentando opacidade das bordas
        line_color="black",
        line_weight=1.0,  # Aumentando espessura das bordas
        smooth_factor=1.0,  # Reduzindo suavização para manter detalhes
        nan_fill_color="LightGray",  # Mudando cor para valores nulos
        legend_name="Índice de Vulnerabilidade TOPSIS",
        bins=bins,  # Usando bins personalizados
    ).add_to(map)

    folium.features.GeoJson(
        resultado_choropleth,
        name="Informações dos setores",
        style_function=lambda x: {
            "color": "transparent",
            "fillColor": "transparent",
            "weight": 0,
        },
        tooltip=folium.features.GeoJsonTooltip(
            fields=cols_indices_to_plot,
            aliases=cols_indices_to_plot,
            labels=True,
            sticky=False,
        ),
        # z_index=450,
        highlight_function=lambda x: {
            "fillColor": "#ffff00",  # Amarelo para highlight
            "color": "#000000",  # Borda preta
            "fillOpacity": 0.7,  # Opacidade maior
            "weight": 2.0,  # Borda mais grossa
        },
    ).add_to(map)

    # Add the marker cluster to the map

    folium.LayerControl().add_to(map)

    # Mostrar estatísticas dos dados para debug
    print(f"\nEstatísticas do {col_result_TP}:")
    print(resultado_choropleth[col_result_TP].describe())
    print(f"\nBins utilizados: {bins}")

    return map


# %%

# TODO - classe para filtrar dados do municipio 1x!!
path_ponderado = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Dados_rakiados-TOP_SYS_COMPLETO.xlsx"
path_ponderado_sem_indicadores_saude = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Dados_rakiados-TOP_SYS_COMPLETO-SEM-INDICADORES-SAUDE-MUNICIPIO.xlsx"
path_dados_totais_pop = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Dados_rakiados-TOP_SYS_COMPLETO-DADOS-TOTAL-POP.xlsx"

# %%
mapa_ponderado = plota_mapa_vulnerabilidade(path_ponderado)
# %%
mapa_ponderado_sem_indicadores_saude = plota_mapa_vulnerabilidade(
    path_ponderado_sem_indicadores_saude
)
mapa_ponderado_sem_indicadores_saude
# %%
mapa_path_dados_totais_pop = plota_mapa_vulnerabilidade(path_dados_totais_pop, 100)
mapa_path_dados_totais_pop
# %%
