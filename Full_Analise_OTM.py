from os import path
import pandas as pd
import numpy as np
import folium
from folium.plugins import (
    MarkerCluster,
    MeasureControl,
    Draw,
    OverlappingMarkerSpiderfier,
    PolyLineTextPath,
)
import geopandas as gpd
import seaborn as sns
import matplotlib.pyplot as plt
from matplotlib.colors import to_hex
import plotly.express as px
import ast
from shapely import length
from shapely.geometry import Polygon

import matplotlib.pyplot as plt
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import re
import matplotlib.pyplot as plt
import seaborn as sns

pd.set_option("display.max_columns", None)
import plotly.io as pio

# Configurar renderer do Plotly - tenta browser, se não funcionar usa o padrão
try:
    # Tenta configurar browser como padrão
    pio.renderers.default = "browser"
except Exception:
    # Se falhar, usa o renderer padrão do sistema
    pass


def mostrar_grafico_plotly(fig, nome_arquivo_html=None):
    """
    Função auxiliar para mostrar gráficos Plotly no navegador de forma robusta.

    Tenta várias estratégias:
    1. Abrir com renderer "browser"
    2. Abrir com renderer padrão
    3. Salvar como HTML e abrir com webbrowser

    Args:
        fig: Figura do Plotly
        nome_arquivo_html: Nome opcional para salvar HTML (padrão: None)
    """
    import webbrowser
    import os

    # Primeiro tenta com renderer browser explícito
    try:
        fig.show(renderer="browser")
        return
    except Exception as e:
        print(f"Erro ao abrir no navegador com renderer 'browser': {e}")

    # Tenta com renderer padrão do sistema
    try:
        fig.show()
        return
    except Exception as e:
        print(f"Erro ao abrir gráfico com renderer padrão: {e}")

    # Se falhar, salva como HTML e abre
    if nome_arquivo_html is None:
        nome_arquivo_html = "grafico_plotly.html"

    try:
        fig.write_html(nome_arquivo_html)
        html_path = os.path.abspath(nome_arquivo_html)
        print(f"Gráfico salvo como '{nome_arquivo_html}'")
        webbrowser.open(f"file://{html_path}")
    except Exception as e:
        print(f"Erro ao salvar/abrir HTML: {e}")
        print("Tente abrir o gráfico manualmente usando fig.show(renderer='browser')")


"""
classe que recebe dois arquivos excel
1 -  baseline 

2 - resultados otimizacao

"""


class AnaliseCenario:
    def __init__(self, path_cenario) -> None:
        self.read_data(path_cenario)

    # TODO: is necessary a dataloader class ?
    def read_data(self, path):
        def str_to_polygon(coords_str):
            # Converte a string para lista de listas de listas
            coords = ast.literal_eval(coords_str)
            return Polygon(coords[0])

        print("LOGGING: READ DATA START")
        self.df_cobertura_equipes = pd.read_excel(path, sheet_name="Sheet1")
        self.df_cobertura_equipes["Setor_Merge"] = (
            self.df_cobertura_equipes.Setor.apply(lambda x: x[:-1])
        )
        self.df_cobertura_equipes["Setor_Merge"] = self.df_cobertura_equipes[
            "Setor_Merge"
        ].astype(int)
        # Cria a coluna com a posição do ranking do IVS (1 = maior IVS)
        self.df_cobertura_equipes["Posicao_Ranking_IVS"] = (
            self.df_cobertura_equipes["IVS"]
            .rank(method="min", ascending=False)
            .astype(int)
        )

        self.df_cobertura_equipes["porcentagem_coberta"] = round(
            self.df_cobertura_equipes.Populacao_Atendida_ESF
            / self.df_cobertura_equipes.Populacao_Total,
            2,
        )
        self.df_fluxo_equipes = pd.read_excel(path, sheet_name="Fluxo_Equipes")
        self.df_custos = pd.read_excel(path, sheet_name="Custos")
        self.df_equipes_criadas = pd.read_excel(path, sheet_name="Equipes_Criadas")
        self.df_fluxo_sec_terc = pd.read_excel(path, sheet_name="Fluxo_Pacientes")
        self.geomtry_sc = gpd.read_file(
            r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\pos_otm\setores_ligth_processado.gpkg"
        )

        self.geomtry_sc = self.geomtry_sc[self.geomtry_sc.CO_MUNICIPIO == 311860]
        self.dados_demografia_sc = pd.read_excel(
            r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\pos_otm\dados_demografia.xlsx",
            sheet_name="Sheet1",
        )
        self.dados_demografia_sc["geometry"] = self.dados_demografia_sc[
            "coordinates"
        ].apply(str_to_polygon)
        print("LOGGING: READ DATA END")

        self.dados_fluxo_emulti = pd.read_excel(path, sheet_name="Aloc_ESF_Emulti")
        self.df_custos = pd.read_excel(path, sheet_name="Custos")

    def plota_mapa_basico_setores_censitarios(
        self, fundo_ivs: bool = True, fundo_cobertura: bool = False
    ):
        print("LOGGING: START TO GENERATE BASIC MAP")
        col_result_TP = "IVS"
        df_data = self.df_cobertura_equipes.copy()
        df_geometry_cs = self.dados_demografia_sc.copy()
        df_end = df_data.merge(
            df_geometry_cs, how="left", right_on="CD_SETOR", left_on="Setor"
        )
        lat_long_contagem = (-19.9321, -44.0539)
        resultado = gpd.GeoDataFrame(df_end, geometry="geometry")
        if not resultado.crs:
            resultado.set_crs(epsg=4326, inplace=True)
        elif resultado.crs.to_epsg() != 4326:
            resultado = resultado.to_crs(epsg=4326)
        map = folium.Map(
            location=[lat_long_contagem[0], lat_long_contagem[1]],
            tiles="cartodbpositron",
            control_scale=True,
            prefer_canvas=True,
            zoom_start=11,
        )
        cols_indices_to_plot = [
            "Setor",
            "Populacao_Total",
            "IVS",
            "Posicao_Ranking_IVS",
            "porcentagem_coberta",
            "Nome_Fantasia_Destino",
        ]

        resultado_choropleth = resultado.copy()
        resultado_choropleth = resultado_choropleth.reset_index()
        resultado_choropleth["id"] = resultado_choropleth.index

        if fundo_ivs:
            min_val = resultado_choropleth[col_result_TP].min()
            max_val = resultado_choropleth[col_result_TP].max()
            print(f"Valor mínimo: {min_val:.4f}")
            print(f"Valor máximo: {max_val:.4f}")

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
            bins = sorted(list(set(bins)))
            folium.Choropleth(
                geo_data=resultado_choropleth,
                name=col_result_TP,
                data=resultado_choropleth,
                columns=["id", col_result_TP],
                key_on="feature.id",
                fill_color="Reds",  # Mudando para vermelho para maior contraste
                fill_opacity=0.5,  # Aumentando opacidade
                line_opacity=0.7,  # Aumentando opacidade das bordas
                line_color="black",
                line_weight=1.0,  # Aumentando espessura das bordas
                smooth_factor=1.0,  # Reduzindo suavização para manter detalhes
                nan_fill_color="LightGray",  # Mudando cor para valores nulos
                legend_name="Índice de Vulnerabilidade TOPSIS",
                bins=bins,  # Usando bins personalizados
            ).add_to(map)

            print(f"\nEstatísticas do {col_result_TP}:")
            print(resultado_choropleth[col_result_TP].describe())
            print(f"\nBins utilizados: {bins}")

        elif fundo_cobertura:
            min_val = resultado_choropleth["porcentagem_coberta"].min()
            max_val = resultado_choropleth["porcentagem_coberta"].max()
            print(f"Valor mínimo: {min_val:.4f}")
            print(f"Valor máximo: {max_val:.4f}")

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
            bins = sorted(list(set(bins)))
            folium.Choropleth(
                geo_data=resultado_choropleth,
                name="porcentagem_coberta",
                data=resultado_choropleth,
                columns=["id", "porcentagem_coberta"],
                key_on="feature.id",
                fill_color="Blues",  #
                fill_opacity=0.9,  # Aumentando opacidade
                line_opacity=0.7,  # Aumentando opacidade das bordas
                line_color="black",
                line_weight=1.0,  # Aumentando espessura das bordas
                smooth_factor=1.0,  # Reduzindo suavização para manter detalhes
                nan_fill_color="LightGray",  # Mudando cor para valores nulos
                legend_name="Cobertura da Populacao",
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

        return map, resultado_choropleth
        # map_cen_6.save("map_cen_10.html")
        # map.save("mapa_teste_2.html")
        # Mostrar estatísticas dos dados para debug

    def plota_fluxo_pacientes(
        self,
        fundo_ivs: bool = True,
    ):
        basic_map, resultado_choropleth = self.plota_mapa_basico_setores_censitarios(
            fundo_ivs=False, fundo_cobertura=True
        )
        lat_origem = "Lat_Demanda"
        long_origem = "Lon_Demanda"
        lat_destino = "Lat_UBS"
        long_destino = "Lon_UBS"

        colunas_necessarias = [
            lat_origem,
            long_origem,
            lat_destino,
            long_destino,
            "Populacao_Atendida_ESF",
        ]
        # Filtrar dados válidos (sem valores nulos nas coordenadas)
        df_fluxo = resultado_choropleth.dropna(
            subset=[lat_origem, long_origem, lat_destino, long_destino]
        )
        df_fluxo = df_fluxo[df_fluxo.Populacao_Atendida_ESF > 0]
        # Normalizar a espessura das linhas baseada na população atendida
        min_pop = df_fluxo["Populacao_Atendida_ESF"].min()
        max_pop = df_fluxo["Populacao_Atendida_ESF"].max()

        # Definir espessura mínima e máxima das linhas
        min_weight = 1
        max_weight = 3

        print(f"População atendida - Min: {min_pop}, Max: {max_pop}")
        print(f"Plotando {len(df_fluxo)} fluxos de pacientes")

        # Adicionar pontos de origem (brancos)
        pontos_origem_unicos = df_fluxo[[lat_origem, long_origem]].drop_duplicates()
        for idx, row in pontos_origem_unicos.iterrows():
            folium.CircleMarker(
                location=[row[lat_origem], row[long_origem]],
                radius=1.5,
                popup=f"Origem: ({row[lat_origem]:.4f}, {row[long_origem]:.4f})",
                color="black",
                fillColor="white",
                fillOpacity=0.8,
                weight=2,
            ).add_to(basic_map)

        # Adicionar pontos de destino (pretos)
        pontos_destino_unicos = df_fluxo[[lat_destino, long_destino]].drop_duplicates()
        for idx, row in pontos_destino_unicos.iterrows():
            folium.CircleMarker(
                location=[row[lat_destino], row[long_destino]],
                radius=2,
                popup=f"UBS: ({row[lat_destino]:.4f}, {row[long_destino]:.4f})",
                color="red",
                fillColor="red",
                fillOpacity=0.9,
                weight=3,
            ).add_to(basic_map)

        # Adicionar linhas/setas proporcionais à população atendida
        for idx, row in df_fluxo.iterrows():
            # Calcular espessura proporcional
            if max_pop > min_pop:
                normalized_pop = (row["Populacao_Atendida_ESF"] - min_pop) / (
                    max_pop - min_pop
                )
                weight = min_weight + (max_weight - min_weight) * normalized_pop
            else:
                weight = min_weight

            # Coordenadas de origem e destino
            coords_origem = [row[lat_origem], row[long_origem]]
            coords_destino = [row[lat_destino], row[long_destino]]

            # Adicionar linha com seta
            folium.PolyLine(
                locations=[coords_origem, coords_destino],
                color="gray",
                weight=weight,
                opacity=0.7,
                popup=f"População Atendida: {row['Populacao_Atendida_ESF']}<br>"
                f"Origem: {coords_origem}<br>"
                f"Destino: {coords_destino}",
            ).add_to(basic_map)

            # Adicionar seta indicativa (usando um marcador triangular no meio da linha)
            # Calcular ponto médio
            lat_meio = (row[lat_origem] + row[lat_destino]) / 2
            lon_meio = (row[long_origem] + row[long_destino]) / 2

            # Calcular ângulo da seta
            import math

            dx = row[long_destino] - row[long_origem]
            dy = row[lat_destino] - row[lat_origem]
            angle = math.degrees(math.atan2(dy, dx))

            # Adicionar marcador de seta
            # folium.Marker(
            # location=[lat_meio, lon_meio],
            # icon=folium.plugins.BeautifyIcon(
            #   icon="arrow-right",
            #   iconShape='marker',
            #   iconSize=(10, 10),
            #  borderColor='red',
            #  backgroundColor='red',
            #  textColor='white'
            # )
            # ).add_to(basic_map)

        print(f"Mapa gerado com sucesso!")
        print(f"- {len(pontos_origem_unicos)} pontos de origem")
        print(f"- {len(pontos_destino_unicos)} pontos de destino (UBS)")
        print(f"- {len(df_fluxo)} fluxos plotados")

        return basic_map, resultado_choropleth

    def plota_fluxo_pacientes_secundario_terciario(self):
        # Obter o mapa base com fluxos primários
        mapa_base, df_base = self.plota_fluxo_pacientes()

        # Preparar dados secundários e terciários
        df_sec = (
            self.df_fluxo_sec_terc[self.df_fluxo_sec_terc.Nivel_Destino == 2]
            .reset_index()
            .copy()
        )
        df_terc = (
            self.df_fluxo_sec_terc[self.df_fluxo_sec_terc.Nivel_Destino == 3]
            .reset_index()
            .copy()
        )

        cols_used = [
            "Fluxo_pacientes",
            "lat_origem",
            "long_origem",
            "lat_destino",
            "long_destino",
        ]

        # Configurações de cores e estilos para cada nível
        config_niveis = {
            "secundario": {
                "df": df_sec,
                "cor_linha": "yellow",
                "cor_destino": "yellow",
                "nome": "Nível Secundário",
                "radius_destino": 2.5,
                "cor_origem": "yellow",
            },
            "terciario": {
                "df": df_terc,
                "cor_linha": "green",
                "cor_destino": "green",
                "nome": "Nível Terciário",
                "radius_destino": 3,
                "cor_origem": "green",
            },
        }

        # Processar cada nível (secundário e terciário)
        for nivel, config in config_niveis.items():
            df_nivel = config["df"]

            # Filtrar dados válidos
            df_nivel_valido = df_nivel.dropna(
                subset=["lat_origem", "long_origem", "lat_destino", "long_destino"]
            )
            df_nivel_valido = df_nivel_valido[df_nivel_valido.Fluxo_pacientes > 0]

            if df_nivel_valido.empty:
                print(f"AVISO: Nenhum dado válido encontrado para {config['nome']}")
                continue

            print(f"Processando {config['nome']}: {len(df_nivel_valido)} fluxos")

            # Normalizar espessura das linhas baseada no fluxo de pacientes
            min_fluxo = df_nivel_valido["Fluxo_pacientes"].min()
            max_fluxo = df_nivel_valido["Fluxo_pacientes"].max()

            # Definir espessura mínima e máxima das linhas para este nível
            min_weight = 1
            max_weight = 3

            print(f"{config['nome']} - Fluxo Min: {min_fluxo}, Max: {max_fluxo}")

            # Adicionar pontos de destino únicos para este nível
            pontos_destino_unicos = df_nivel_valido[
                ["lat_destino", "long_destino"]
            ].drop_duplicates()

            for idx, row in pontos_destino_unicos.iterrows():
                folium.CircleMarker(
                    location=[row["lat_destino"], row["long_destino"]],
                    radius=config["radius_destino"],
                    popup=f"{config['nome']}: ({row['lat_destino']:.4f}, {row['long_destino']:.4f})",
                    color=config["cor_origem"],
                    fillColor=config["cor_destino"],
                    fillOpacity=0.8,
                    weight=2,
                ).add_to(mapa_base)

            # Adicionar linhas proporcionais ao fluxo de pacientes
            for idx, row in df_nivel_valido.iterrows():
                # Calcular espessura proporcional
                if max_fluxo > min_fluxo:
                    normalized_fluxo = (row["Fluxo_pacientes"] - min_fluxo) / (
                        max_fluxo - min_fluxo
                    )
                    weight = min_weight + (max_weight - min_weight) * normalized_fluxo
                else:
                    if nivel == "terciario":
                        weight = 5
                    else:
                        weight = max_weight

                # Coordenadas de origem e destino
                coords_origem = [row["lat_origem"], row["long_origem"]]
                coords_destino = [row["lat_destino"], row["long_destino"]]

                # Adicionar linha
                folium.PolyLine(
                    locations=[coords_origem, coords_destino],
                    color=config["cor_linha"],
                    weight=weight,
                    opacity=0.6,
                    popup=f"{config['nome']}<br>"
                    f"Fluxo de Pacientes: {row['Fluxo_pacientes']}<br>"
                    f"Origem: {coords_origem}<br>"
                    f"Destino: {coords_destino}",
                    tooltip=f"{config['nome']}: {row['Fluxo_pacientes']} pacientes",
                ).add_to(mapa_base)

            print(
                f"{config['nome']} plotado: {len(pontos_destino_unicos)} destinos, {len(df_nivel_valido)} fluxos"
            )

        # Criar legenda customizada
        legenda_html = """
        <div style="position: fixed; 
                    top: 10px; right: 10px; width: 200px; height: 120px; 
                    background-color: white; border:2px solid grey; z-index:9999; 
                    font-size:14px; padding: 10px">
        <h4>Legenda dos Fluxos</h4>
        <p><span style="color:gray;">■</span> Fluxo Primário (ESF)</p>
        <p><span style="color:blue;">■</span> Fluxo Secundário</p>
        <p><span style="color:green;">■</span> Fluxo Terciário</p>
        <p><i>Espessura ∝ Volume de pacientes</i></p>
        </div>
        """
        mapa_base.get_root().html.add_child(folium.Element(legenda_html))

        print("LOGGING: MAPA COMPLETO GERADO COM SUCESSO!")
        print("- Fluxos primários (cinza): ESF")
        print("- Fluxos secundários (amarelo): Nível 2")
        print("- Fluxos terciários (verde): Nível 3")

        return mapa_base, df_base

    def plota_fluxo_Emulti(self):
        # TODO: Parece que estou com indices errados, ja que estou alocando EMulti em unidades que nao estao abertas. Revisar!

        basic_map, resultado_choropleth = self.plota_mapa_basico_setores_censitarios(
            fundo_ivs=False, fundo_cobertura=True
        )

        df = self.dados_fluxo_emulti.copy()

        for idx, row in df.iterrows():
            # ponto de origem ESF
            folium.CircleMarker(
                location=[row["lat_origem_esf"], row["long_origem_esf"]],
                radius=1.5,
                # popup=f"Cnes{})",
                color="yellow",
                fillColor="yellow",
                fillOpacity=0.8,
                weight=2,
            ).add_to(basic_map)

            # ponto de Destino Emulti
            folium.CircleMarker(
                location=[row["lat_emulti"], row["long_emulti"]],
                radius=1.5,
                popup=f"Cnes Emulti {row["cnes_eq_emulti"]})",
                color="black",
                fillColor="black",
                fillOpacity=0.8,
                weight=2,
            ).add_to(basic_map)

            coords_origem = [row["lat_origem_esf"], row["long_origem_esf"]]
            coords_destino = [row["lat_emulti"], row["long_emulti"]]

            folium.PolyLine(
                locations=[coords_origem, coords_destino],
                color="black",
                weight=2,
                opacity=0.6,
                # popup=f"{config['nome']}<br>"
                # f"Fluxo de Pacientes: {row['Fluxo_pacientes']}<br>"
                # f"Origem: {coords_origem}<br>"
                # f"Destino: {coords_destino}",
                # tooltip=f"{config['nome']}: {row['Fluxo_pacientes']} pacientes",
            ).add_to(basic_map)

        # basic_map.save("map_fluxo_Emulti_2.html")
        return basic_map

    def plota_fluxo_equipes(self):
        print("LOGGING: INICIANDO PLOTAGEM DE FLUXOS DE EQUIPES")

        # Obter o mapa base com fluxos de pacientes
        mapa_base, df_base = self.plota_fluxo_pacientes()

        # Preparar dados dos três tipos de equipes
        df_ESF = self.df_fluxo_equipes[
            self.df_fluxo_equipes.tipo_equipe == 1
        ].reset_index()
        df_ESB = self.df_fluxo_equipes[
            self.df_fluxo_equipes.tipo_equipe == 2
        ].reset_index()
        df_Enasf = self.df_fluxo_equipes[
            self.df_fluxo_equipes.tipo_equipe == 3
        ].reset_index()

        # Identificar as colunas de coordenadas (assumindo nomes padrão)
        # Ajuste os nomes das colunas conforme necessário
        colunas_coords = ["lat_origem", "long_origem", "lat_destino", "long_destino"]

        # Se as colunas tiverem nomes diferentes, substitua aqui:
        # Exemplo alternativo: ['Lat_Origem', 'Lon_Origem', 'Lat_Destino', 'Lon_Destino']

        # Configurações de cores e estilos para cada tipo de equipe
        config_equipes = {
            "ESF": {
                "df": df_ESF,
                "cor_linha": "purple",
                "cor_origem": "purple",
                "cor_destino": "darkviolet",
                "nome": "Equipe ESF",
                "radius_origem": 6,
                "radius_destino": 8,
                "simbolo": "●",
            },
            "ESB": {
                "df": df_ESB,
                "cor_linha": "orange",
                "cor_origem": "orange",
                "cor_destino": "darkorange",
                "nome": "Equipe ESB",
                "radius_origem": 6,
                "radius_destino": 8,
                "simbolo": "▲",
            },
            "Enasf": {
                "df": df_Enasf,
                "cor_linha": "red",
                "cor_origem": "red",
                "cor_destino": "darkred",
                "nome": "Equipe Enasf",
                "radius_origem": 6,
                "radius_destino": 8,
                "simbolo": "■",
            },
        }

        # Processar cada tipo de equipe
        for tipo_equipe, config in config_equipes.items():
            df_equipe = config["df"]

            if df_equipe.empty:
                print(f"AVISO: Nenhum dado encontrado para {config['nome']}")
                continue

            # Verificar se as colunas de coordenadas existem
            colunas_existentes = [
                col for col in colunas_coords if col in df_equipe.columns
            ]
            if len(colunas_existentes) < 4:
                print(
                    f"AVISO: Colunas de coordenadas não encontradas para {config['nome']}"
                )
                print(f"Colunas disponíveis: {list(df_equipe.columns)}")
                continue

            # Filtrar dados válidos
            df_equipe_valido = df_equipe.dropna(subset=colunas_coords)

            if df_equipe_valido.empty:
                print(f"AVISO: Nenhum dado válido encontrado para {config['nome']}")
                continue

            print(f"Processando {config['nome']}: {len(df_equipe_valido)} fluxos")

            # Definir espessura das linhas (pode ser constante ou baseada em alguma coluna)
            # Se houver uma coluna de quantidade/fluxo, use para normalizar
            peso_linha = 2.5  # Peso padrão

            # Se existir uma coluna de fluxo/quantidade, descomente e ajuste:
            # if 'quantidade_equipes' in df_equipe_valido.columns:
            #     min_qtd = df_equipe_valido['quantidade_equipes'].min()
            #     max_qtd = df_equipe_valido['quantidade_equipes'].max()

            # Adicionar pontos de origem únicos
            pontos_origem_unicos = df_equipe_valido[
                ["lat_origem", "long_origem"]
            ].drop_duplicates()

            for idx, row in pontos_origem_unicos.iterrows():
                folium.CircleMarker(
                    location=[row["lat_origem"], row["long_origem"]],
                    radius=config["radius_origem"],
                    popup=f"{config['nome']} - Origem<br>Lat: {row['lat_origem']:.4f}<br>Lon: {row['long_origem']:.4f}",
                    color="black",
                    fillColor=config["cor_origem"],
                    fillOpacity=0.7,
                    weight=2,
                ).add_to(mapa_base)

            # Adicionar pontos de destino únicos
            pontos_destino_unicos = df_equipe_valido[
                ["lat_destino", "long_destino"]
            ].drop_duplicates()

            for idx, row in pontos_destino_unicos.iterrows():
                folium.CircleMarker(
                    location=[row["lat_destino"], row["long_destino"]],
                    radius=config["radius_destino"],
                    popup=f"{config['nome']} - Destino<br>Lat: {row['lat_destino']:.4f}<br>Lon: {row['long_destino']:.4f}",
                    color="black",
                    fillColor=config["cor_destino"],
                    fillOpacity=0.8,
                    weight=2,
                ).add_to(mapa_base)

            # Adicionar linhas conectando origem e destino
            for idx, row in df_equipe_valido.iterrows():
                coords_origem = [row["lat_origem"], row["long_origem"]]
                coords_destino = [row["lat_destino"], row["long_destino"]]

                # Informações para popup (ajuste conforme colunas disponíveis)
                info_popup = f"{config['nome']}<br>"
                info_popup += f"Origem: {coords_origem}<br>"
                info_popup += f"Destino: {coords_destino}<br>"

                # Adicionar informações extras se disponíveis
                if "nome_origem" in df_equipe_valido.columns:
                    info_popup += f"Local Origem: {row.get('nome_origem', 'N/A')}<br>"
                if "nome_destino" in df_equipe_valido.columns:
                    info_popup += f"Local Destino: {row.get('nome_destino', 'N/A')}<br>"

                folium.PolyLine(
                    locations=[coords_origem, coords_destino],
                    color=config["cor_linha"],
                    weight=peso_linha,
                    opacity=0.6,
                    popup=info_popup,
                    tooltip=f"{config['nome']}",
                ).add_to(mapa_base)

            print(
                f"{config['nome']} plotado: {len(pontos_origem_unicos)} origens, {len(pontos_destino_unicos)} destinos, {len(df_equipe_valido)} fluxos"
            )

        # Criar legenda customizada combinada
        legenda_html = """
        <div style="position: fixed; 
                    top: 10px; right: 10px; width: 220px; height: 180px; 
                    background-color: white; border:2px solid grey; z-index:9999; 
                    font-size:13px; padding: 10px">
        <h4 style="margin: 0 0 8px 0;">Legenda Completa</h4>
        <p style="margin: 2px 0;"><span style="color:gray;">●</span> Fluxo Pacientes (ESF)</p>
        <p style="margin: 2px 0;"><span style="color:blue;">●</span> Fluxo Secundário</p>
        <p style="margin: 2px 0;"><span style="color:green;">●</span> Fluxo Terciário</p>
        <hr style="margin: 5px 0;">
        <p style="margin: 2px 0;"><span style="color:purple;">●</span> Equipes ESF</p>
        <p style="margin: 2px 0;"><span style="color:orange;">▲</span> Equipes ESB</p>
        <p style="margin: 2px 0;"><span style="color:red;">■</span> Equipes Enasf</p>
        <p style="margin: 5px 0 0 0;"><i>Espessura ∝ Volume</i></p>
        </div>
        """
        mapa_base.get_root().html.add_child(folium.Element(legenda_html))

        print("LOGGING: MAPA DE EQUIPES GERADO COM SUCESSO!")
        print("- Fluxos de pacientes: cinza/azul/verde")
        print("- Fluxos de equipes ESF: roxo")
        print("- Fluxos de equipes ESB: laranja")
        print("- Fluxos de equipes Enasf: vermelho")

        return mapa_base, df_base

    def analisa_cobertura_por_faixas_ivs(self, tamanho_faixa=20):
        """
        Analisa a cobertura dos setores censitários por faixas de IVS (vulnerabilidade).

        Args:
            tamanho_faixa (int): Tamanho de cada faixa para análise (ex: 20 = top 20, 21-40, etc.)

        Returns:
            tuple: (figura matplotlib, dataframe com resultados)
        """

        print("LOGGING: INICIANDO ANÁLISE DE COBERTURA POR FAIXAS DE IVS")

        # Trabalhar com cópia do dataframe
        df = self.df_cobertura_equipes.copy()

        # Verificar se existe a coluna de ranking IVS
        if "Posicao_Ranking_IVS" not in df.columns:
            print("ERRO: Coluna 'Posicao_Ranking_IVS' não encontrada!")
            return None, None

        # Definir cobertura (população atendida > 0)
        df["coberto"] = df["Populacao_Atendida_ESF"] > 0

        total_setores = len(df)
        print(f"Total de setores: {total_setores}")
        print(f"Setores cobertos: {df['coberto'].sum()}")
        print(f"Setores não cobertos: {(~df['coberto']).sum()}")

        # Criar faixas baseadas no ranking IVS
        num_faixas = int(np.ceil(total_setores / tamanho_faixa))

        resultados = []

        for i in range(num_faixas):
            inicio_faixa = i * tamanho_faixa + 1
            fim_faixa = min((i + 1) * tamanho_faixa, total_setores)

            # Filtrar setores nesta faixa
            setores_faixa = df[
                (df["Posicao_Ranking_IVS"] >= inicio_faixa)
                & (df["Posicao_Ranking_IVS"] <= fim_faixa)
            ]

            total_na_faixa = len(setores_faixa)
            cobertos_na_faixa = setores_faixa["coberto"].sum()
            nao_cobertos_na_faixa = total_na_faixa - cobertos_na_faixa
            percentual_cobertura = (
                (cobertos_na_faixa / total_na_faixa * 100) if total_na_faixa > 0 else 0
            )

            # Calcular IVS médio da faixa
            ivs_medio = setores_faixa["IVS"].mean()

            resultados.append(
                {
                    "Faixa": f"{inicio_faixa}-{fim_faixa}",
                    "Inicio_Faixa": inicio_faixa,
                    "Fim_Faixa": fim_faixa,
                    "Total_Setores": total_na_faixa,
                    "Setores_Cobertos": cobertos_na_faixa,
                    "Setores_Nao_Cobertos": nao_cobertos_na_faixa,
                    "Percentual_Cobertura": percentual_cobertura,
                    "IVS_Medio": ivs_medio,
                    "Nivel_Criticidade": (
                        "Muito Alto"
                        if inicio_faixa <= 20
                        else (
                            "Alto"
                            if inicio_faixa <= 40
                            else (
                                "Médio"
                                if inicio_faixa <= 60
                                else "Baixo" if inicio_faixa <= 80 else "Muito Baixo"
                            )
                        )
                    ),
                }
            )

        df_resultados = pd.DataFrame(resultados)

        # Criar gráfico
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))

        # Gráfico 1: Barras empilhadas mostrando cobertos vs não cobertos
        x_pos = np.arange(len(df_resultados))
        width = 0.8

        bars1 = ax1.bar(
            x_pos,
            df_resultados["Setores_Cobertos"],
            width,
            label="Setores Cobertos",
            color="#2E8B57",
            alpha=0.8,
        )
        bars2 = ax1.bar(
            x_pos,
            df_resultados["Setores_Nao_Cobertos"],
            width,
            bottom=df_resultados["Setores_Cobertos"],
            label="Setores Não Cobertos",
            color="#DC143C",
            alpha=0.8,
        )

        ax1.set_xlabel("Faixas de Ranking IVS (1 = Mais Vulnerável)")
        ax1.set_ylabel("Número de Setores")
        ax1.set_title(
            "Cobertura de Setores Censitários por Faixas de Vulnerabilidade (IVS)"
        )
        ax1.set_xticks(x_pos)
        ax1.set_xticklabels(df_resultados["Faixa"], rotation=45, ha="right")
        ax1.legend()
        ax1.grid(axis="y", alpha=0.3)

        # Adicionar valores nas barras
        for i, (cobertos, nao_cobertos, total) in enumerate(
            zip(
                df_resultados["Setores_Cobertos"],
                df_resultados["Setores_Nao_Cobertos"],
                df_resultados["Total_Setores"],
            )
        ):
            ax1.text(
                i,
                cobertos / 2,
                str(cobertos),
                ha="center",
                va="center",
                fontweight="bold",
                color="white",
            )
            if nao_cobertos > 0:
                ax1.text(
                    i,
                    cobertos + nao_cobertos / 2,
                    str(nao_cobertos),
                    ha="center",
                    va="center",
                    fontweight="bold",
                    color="white",
                )
            ax1.text(
                i, total + 1, f"{total}", ha="center", va="bottom", fontweight="bold"
            )

        # Gráfico 2: Percentual de cobertura por faixa
        colors = [
            "#8B0000",
            "#DC143C",
            "#FF6347",
            "#FFA500",
            "#32CD32",
        ]  # Do mais crítico ao menos crítico
        bars3 = ax2.bar(
            x_pos,
            df_resultados["Percentual_Cobertura"],
            width,
            color=colors[: len(df_resultados)],
            alpha=0.7,
        )

        ax2.set_xlabel("Faixas de Ranking IVS (1 = Mais Vulnerável)")
        ax2.set_ylabel("Percentual de Cobertura (%)")
        ax2.set_title("Percentual de Cobertura por Faixa de Vulnerabilidade")
        ax2.set_xticks(x_pos)
        ax2.set_xticklabels(df_resultados["Faixa"], rotation=45, ha="right")
        ax2.set_ylim(0, 100)
        ax2.grid(axis="y", alpha=0.3)

        # Adicionar percentuais nas barras
        for i, pct in enumerate(df_resultados["Percentual_Cobertura"]):
            ax2.text(
                i, pct + 2, f"{pct:.1f}%", ha="center", va="bottom", fontweight="bold"
            )

        # Adicionar linha de referência (meta de cobertura)
        ax2.axhline(
            y=100, color="red", linestyle="--", alpha=0.5, label="Cobertura Total"
        )
        ax2.legend()

        plt.tight_layout()

        # Imprimir resumo
        print("\n" + "=" * 60)
        print("RESUMO DA ANÁLISE DE COBERTURA POR VULNERABILIDADE")
        print("=" * 60)

        for _, row in df_resultados.iterrows():
            print(
                f"Faixa {row['Faixa']} ({row['Nivel_Criticidade']}): "
                f"{row['Setores_Cobertos']}/{row['Total_Setores']} setores cobertos "
                f"({row['Percentual_Cobertura']:.1f}%)"
            )

        print(
            f"\nCobertura geral: {df['coberto'].sum()}/{total_setores} setores "
            f"({df['coberto'].sum()/total_setores*100:.1f}%)"
        )

        # Análise dos mais vulneráveis
        top20_cobertos = (
            df_resultados.iloc[0]["Setores_Cobertos"] if len(df_resultados) > 0 else 0
        )
        top20_total = (
            df_resultados.iloc[0]["Total_Setores"] if len(df_resultados) > 0 else 0
        )
        print(
            f"\nSetores mais vulneráveis (Top {min(tamanho_faixa, total_setores)}): "
            f"{top20_cobertos}/{top20_total} cobertos "
            f"({(top20_cobertos/top20_total*100) if top20_total > 0 else 0:.1f}%)"
        )

        return fig, df_resultados

    def analise_descritiva_cenario(self):
        df_rt, _ = self.analisa_cobertura_por_faixas_ivs(tamanho_faixa=100)
        b = 0

        # Perguntas que quero responder - por equipe!:
        # 1 - Porcentagem total da populacao coberta
        # 2 - Quantos setores censitarios com maior IVS foram cobertos ? Ex: dos 20 mais criticos, cobri 18, entre 20 - 40, cobri 20, etc, etc.
        # 3 - Plotar analise dos custos!

    def plota_acessibilidade_geografica_cenario(self):

        df = pd.DataFrame(
            {
                "dist": self.df_cobertura_equipes.Distancia.to_list(),
                "pop": self.df_cobertura_equipes.Populacao_Atendida_ESF.to_list(),
            }
        ).dropna()

        # Definindo os bins de 0.5 em 0.5 km, cobrindo o range dos dados
        min_dist = df["dist"].min()
        max_dist = df["dist"].max()
        bin_edges = list(
            np.arange(
                0,
                max_dist + 0.5,
                0.5,
            )
        )
        fig = px.histogram(
            df,
            x="dist",
            y="pop",  # pesos
            histfunc="sum",  # soma as populações em cada bin
            labels={"dist": "Distância (km)", "pop": "População atendida"},
            title="Distribuição ponderada da população por distância (ESF)",
            category_orders={"dist": bin_edges},
            nbins=len(bin_edges) - 1,
        )
        fig.update_traces(xbins=dict(start=bin_edges[0], end=bin_edges[-1], size=0.5))
        fig.update_layout(bargap=0.05)

        fig.write_html("dist_distancia_cenario.html")
        # return fig


class AnaliseBaselineMapaSus:
    def __init__(self, path_data_sus) -> None:
        self.format_baseline_data(path_data_sus)

    def format_baseline_data(self, path_data_sus):
        def str_to_float_list_loose(s: str) -> list[float]:
            nums = re.findall(
                r"-?\d+(?:\.\d+)?", s
            )  # encontra ints e floats (com sinal)
            return [float(x) for x in nums]

        def calcula_populacao_atendida_real(vetor_pop):
            pop_atendida = []
            for i in range(len(vetor_pop)):
                if i == 0:
                    pop_atendida.append(vetor_pop[i])
                else:
                    pop_atendida.append(vetor_pop[i] - vetor_pop[i - 1])
            return pop_atendida

        self.df_baseline = pd.read_excel(path_data_sus, sheet_name="df_merge_aux")
        self.df_baseline["qntd_alocada_por_nivel_dist_eSF"] = self.df_baseline[
            "qntd_alocada_por_nivel_dist_eSF"
        ].map(str_to_float_list_loose)

        self.df_baseline["qntd_alocada_por_nivel_dist_eSB"] = self.df_baseline[
            "qntd_alocada_por_nivel_dist_eSB"
        ].map(str_to_float_list_loose)

        self.df_baseline["Distancia_eSF"] = self.df_baseline["Distancia_eSF"].map(
            str_to_float_list_loose
        )

        self.df_baseline["Distancia_eSB"] = self.df_baseline["Distancia_eSB"].map(
            str_to_float_list_loose
        )

        self.df_baseline["pop_atendida_por_distancia_eSF"] = (
            self.df_baseline.qntd_alocada_por_nivel_dist_eSF.apply(
                lambda x: calcula_populacao_atendida_real(x)
            )
        )
        self.df_baseline["pop_atendida_por_distancia_eSB"] = (
            self.df_baseline.qntd_alocada_por_nivel_dist_eSB.apply(
                lambda x: calcula_populacao_atendida_real(x)
            )
        )

        self.df_equipes_bruto = pd.read_excel(path_data_sus, sheet_name="unidades_full")
        self.df_baseline["id_setor"] = self.df_baseline["id_setor"].astype(int)

        self.custos_mensais = {
            "EMULTI - EQUIPE MULTIPROFISSIONAL NA AT. PRIMARIA A SAUDE": 92000,
            "ESB - EQUIPE DE SAUDE BUCAL": 22000,
            "ESF - EQUIPE DE SAUDE DA FAMILIA": 50000,
            "Custo Fixo Mensal": 122775,
        }
        # TODO: Vai ser fundamental a analise de acessibilidade geografica e capacidade maxima de atendimento nas UBS!
        self.calcula_custos_reais()
        df_equipes = pd.read_excel(path_data_sus, sheet_name="unidades_full")
        self.df_emulti_reais = df_equipes[
            ((df_equipes.SG_EQUIPE == "eMulti") & (df_equipes.ST_EQUIPE_VALIDA == "S"))
        ].reset_index()

    def calcula_custos_reais(self):
        eqs_analise = [70, 71, 72]
        df_an = self.df_equipes_bruto[
            self.df_equipes_bruto["TP_EQUIPE"].isin(eqs_analise)
        ]
        df_agg = (
            df_an.groupby(by=["DS_EQUIPE"])
            .agg(Qntd_Equipes=("TP_EQUIPE", "count"))
            .reset_index()
        )
        df_agg["Custo_Mensal"] = df_agg.apply(
            lambda x: self.custos_mensais[x.DS_EQUIPE] * x.Qntd_Equipes, axis=1
        )
        self.custo_equipes_real = df_agg["Custo_Mensal"].sum()
        self.custo_fixo_real = (
            self.custos_mensais["Custo Fixo Mensal"] * df_an.NO_FANTASIA.nunique()
        )
        self.custo_total = self.custo_equipes_real + self.custo_fixo_real
        self.custo_equipes_real = df_agg.copy()
        print(f"Custo Total Real: {self.custo_total}")

    def plota_acessibilidade_geografica(self):
        df = self.df_baseline.copy()
        cols = (
            "pop_atendida_por_distancia_eSF",
            "pop_atendida_por_distancia_eSB",
            "Distancia_eSF",
            "Distancia_eSB",
        )
        df_aux = df[
            [
                "pop_atendida_por_distancia_eSF",
                "pop_atendida_por_distancia_eSB",
                "Distancia_eSF",
                "Distancia_eSB",
            ]
        ].copy()
        distancias_ESF = list()
        populacao_ESF = list()
        distancias_ESB = list()
        populacao_ESB = list()

        for _, row in df_aux.iterrows():
            distancias_ESF.extend(row.Distancia_eSF)
            populacao_ESF.extend(row.pop_atendida_por_distancia_eSF)
            distancias_ESB.extend(row.Distancia_eSB)
            populacao_ESB.extend(row.pop_atendida_por_distancia_eSB)

        df = pd.DataFrame({"dist": distancias_ESF, "pop": populacao_ESF}).dropna()

        # Definindo os bins de 0.5 em 0.5 km, cobrindo o range dos dados
        min_dist = df["dist"].min()
        max_dist = df["dist"].max()
        bin_edges = list(
            np.arange(
                0,
                max_dist + 0.5,
                0.5,
            )
        )
        fig = px.histogram(
            df,
            x="dist",
            y="pop",  # pesos
            histfunc="sum",  # soma as populações em cada bin
            labels={"dist": "Distância (km)", "pop": "População atendida"},
            title="Distribuição ponderada da população por distância (ESF)",
            category_orders={"dist": bin_edges},
            nbins=len(bin_edges) - 1,
        )
        fig.update_traces(xbins=dict(start=bin_edges[0], end=bin_edges[-1], size=0.5))
        fig.update_layout(bargap=0.05)
        # df[df.dist > 1.5]["pop"].sum()
        # fig.write_html("dist_distancia.html")
        # return fig
        fig.write_image("comparacao_cobertura.png", width=1400, height=1200)


class ComparaResultadoBaseline:
    def __init__(self, path_cenario, path_baseline) -> None:
        self.baseline = AnaliseBaselineMapaSus(path_baseline)
        self.cenario = AnaliseCenario(path_cenario)
        self.merge_baseline_cenario()

    def merge_baseline_cenario(self):
        df_baseline = self.baseline.df_baseline.copy()
        df_cenario = self.cenario.df_cobertura_equipes.copy()
        self.df_merge = df_baseline.merge(
            df_cenario, how="outer", right_on="Setor_Merge", left_on="id_setor"
        )
        # cols_compare_ESF = 'pop_captada_eSF', 'Populacao_Atendida_ESF'
        # cols_compare_ESB = 'pop_captada_eSB',  'Populacao_Atendida_ESB'

    def plota_comparativo_acessibilidade(self):
        self.cenario.plota_acessibilidade_geografica_cenario()
        self.baseline.plota_acessibilidade_geografica()
        # fig_cenario = self.plota_acessibilidade_geografica_cenario

    def compara_quantidade_equipes(self):
        df_equipes_criadas = self.cenario.df_equipes_criadas.copy()
        df_fluxo_eqs = self.cenario.df_fluxo_equipes[
            self.cenario.df_fluxo_equipes.Valor_Variavel > 0
        ].copy()
        map_indices = {1: "eSF", 2: "eSB", 3: "eMulti"}
        eqps_fim_modelo = (
            df_fluxo_eqs.groupby(by=["tipo_equipe"])
            .agg(qntd_equipes=("cnes_eq", "count"))
            .reset_index()
        )
        eqs_esf_criadas = df_equipes_criadas.eq_ESF_criadas.sum()
        eqs_esb_criadas = df_equipes_criadas.eq_ESB_criadas.sum()
        eqs_emulti_criadas = df_equipes_criadas.eq_ENASF_criadas.sum()
        eqps_fim_modelo["Equipe"] = eqps_fim_modelo.tipo_equipe.apply(
            lambda x: map_indices[x]
        )
        eqps_fim_modelo["Equipes_criadas"] = 0

        # Função auxiliar para atualizar ou adicionar linhas conforme necessário
        def set_equipes_criadas(tipo_equipe_num, equipes_criadas_val, nome_equipe):
            if "tipo_equipe" in eqps_fim_modelo.columns:
                if (eqps_fim_modelo.tipo_equipe == tipo_equipe_num).any():
                    eqps_fim_modelo.loc[
                        eqps_fim_modelo.tipo_equipe == tipo_equipe_num,
                        "Equipes_criadas",
                    ] = equipes_criadas_val
                else:
                    # Cria nova linha caso tipo_equipe não exista
                    nova_linha = {
                        "tipo_equipe": tipo_equipe_num,
                        "Equipe": nome_equipe,
                        "qntd_equipes": 0,
                        "Equipes_criadas": equipes_criadas_val,
                    }
                    eqps_fim_modelo.loc[len(eqps_fim_modelo)] = nova_linha
            else:
                # Caso o dataframe não tenha a coluna, nada a fazer (optionally: raise/log)
                pass

        set_equipes_criadas(1, eqs_esf_criadas, "eSF")
        set_equipes_criadas(2, eqs_esb_criadas, "eSB")
        set_equipes_criadas(3, eqs_emulti_criadas, "eMulti")
        eqps_fim_modelo["Total de Equipes Modelo"] = (
            eqps_fim_modelo.qntd_equipes + eqps_fim_modelo.Equipes_criadas
        )

        eqs_baseline_total = (
            self.baseline.df_equipes_bruto.SG_EQUIPE.value_counts().reset_index()
        )
        df_equipes_real = eqs_baseline_total[
            eqs_baseline_total.SG_EQUIPE.isin(["eSF", "eSB", "eMulti"])
        ]

        df_equipes_real = df_equipes_real.rename(
            columns={"SG_EQUIPE": "Equipe", "count": "Total de Equipes Real"}
        )

        df_final = eqps_fim_modelo.merge(df_equipes_real, on="Equipe", how="left")

        # Criar gráfico comparativo de equipes
        self.cria_grafico_comparativo_equipes(df_final)

    def cria_grafico_comparativo_equipes(self, df_final):
        """
        Cria gráfico comparativo entre equipes reais e modelo com 2 subplots
        """
        import plotly.graph_objects as go
        from plotly.subplots import make_subplots

        # Preparar dados para o gráfico
        df_plot = df_final.copy()

        # Definir cores consistentes
        cores = {
            "real": "#1f77b4",  # Azul
            "modelo": "#7f7f7f",  # Cinza
            "existentes": "#ff7f0e",  # Laranja
            "criadas": "#2ca02c",  # Verde
        }

        # Criar figura com 2 subplots
        fig = make_subplots(
            rows=2,
            cols=1,
            subplot_titles=(
                "Total de Equipes Modelo x Real",
                "Equipes Criadas e Mantidas - Modelo",
            ),
            specs=[
                [{"type": "bar"}],
                [{"type": "bar"}],
            ],
            vertical_spacing=0.25,
        )

        # ============================================================================================================
        # GRÁFICO 1: Comparação Total de Equipes Modelo vs Real
        # ============================================================================================================

        # Adicionar barra para equipes reais
        fig.add_trace(
            go.Bar(
                x=df_plot["Equipe"],
                y=df_plot["Total de Equipes Real"],
                name="Total de Equipes Real",
                marker_color=cores["real"],
                text=df_plot["Total de Equipes Real"],
                textposition="outside",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        # Adicionar barra para equipes do modelo
        fig.add_trace(
            go.Bar(
                x=df_plot["Equipe"],
                y=df_plot["Total de Equipes Modelo"],
                name="Total de Equipes Modelo",
                marker_color=cores["modelo"],
                text=df_plot["Total de Equipes Modelo"],
                textposition="outside",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        # ============================================================================================================
        # GRÁFICO 2: Equipes Criadas e Mantidas no Modelo
        # ============================================================================================================

        # Adicionar barra para equipes existentes (mantidas)
        fig.add_trace(
            go.Bar(
                x=df_plot["Equipe"],
                y=df_plot["qntd_equipes"],
                name="Equipes Mantidas (Modelo)",
                marker_color=cores["existentes"],
                text=df_plot["qntd_equipes"],
                textposition="outside",
                showlegend=True,
            ),
            row=2,
            col=1,
        )

        # Adicionar barra para equipes criadas
        fig.add_trace(
            go.Bar(
                x=df_plot["Equipe"],
                y=df_plot["Equipes_criadas"],
                name="Equipes Criadas (Modelo)",
                marker_color=cores["criadas"],
                text=df_plot["Equipes_criadas"],
                textposition="outside",
                showlegend=True,
            ),
            row=2,
            col=1,
        )

        # ============================================================================================================
        # CONFIGURAÇÃO DO LAYOUT
        # ============================================================================================================

        fig.update_layout(
            height=1000,
            width=1200,
            title_text="Análise Comparativa de Equipes: Real vs Modelo",
            title_x=0.5,
            title_font_size=16,
            showlegend=True,
            paper_bgcolor="#ffffff",
            plot_bgcolor="#ffffff",
            margin=dict(t=90, b=90, l=80, r=40),
            legend=dict(
                orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5
            ),
            barmode="group",
            bargap=0.2,
        )

        # Configurar eixos
        fig.update_xaxes(title_text="Tipo de Equipe", row=1, col=1)
        fig.update_xaxes(title_text="Tipo de Equipe", row=2, col=1)

        fig.update_yaxes(title_text="Quantidade de Equipes", row=1, col=1)
        fig.update_yaxes(title_text="Quantidade de Equipes", row=2, col=1)

        # Rotacionar labels do eixo x para melhor legibilidade
        fig.update_xaxes(tickangle=45, row=1, col=1)
        fig.update_xaxes(tickangle=45, row=2, col=1)

        # Ajustes globais de traços
        fig.update_traces(cliponaxis=False)

        # Salvar o gráfico
        fig.write_html("comparacao_equipes_real_vs_modelo.html")
        fig.write_image(
            "comparacao_equipes_real_vs_modelo.png", width=1200, height=1000
        )

        print("Gráfico comparativo de equipes criado e salvo!")
        print(f"Arquivos gerados:")
        print(f"- comparacao_equipes_real_vs_modelo.html")
        print(f"- comparacao_equipes_real_vs_modelo.png")

        # Mostrar resumo dos dados
        print("\nResumo dos dados:")
        for _, row in df_plot.iterrows():
            print(f"{row['Equipe']}:")
            print(f"  Real: {row['Total de Equipes Real']}")
            print(f"  Modelo Total: {row['Total de Equipes Modelo']}")
            print(f"    - Existentes: {row['qntd_equipes']}")
            print(f"    - Criadas: {row['Equipes_criadas']}")
            print()

        # return fig

    def plota_comparacao_equipes_emulti(self, df_merge):
        df_plot = df_merge.copy()
        df_plot["cnes_eq_multi"] = df_plot["cnes_eq_emulti"].fillna(
            df_plot["CO_EQUIPE"]
        )

        # Renomear coluna baseline para real conforme solicitado
        if "EQUIPES_VINCULADAS_baseline" in df_plot.columns:
            df_plot["EQUIPES_VINCULADAS_real"] = df_plot["EQUIPES_VINCULADAS_baseline"]

        # Filtrar apenas linhas com dados válidos e ordenar
        df_plot = df_plot[df_plot["cnes_eq_multi"].notna()].copy()
        df_plot = df_plot.sort_values("cnes_eq_multi").reset_index(drop=True)

        # Preparar dados para plotly (formato longo)
        # Garantir que a coluna EQUIPES_VINCULADAS_real existe
        if "EQUIPES_VINCULADAS_real" not in df_plot.columns:
            if "EQUIPES_VINCULADAS_baseline" in df_plot.columns:
                df_plot["EQUIPES_VINCULADAS_real"] = df_plot[
                    "EQUIPES_VINCULADAS_baseline"
                ]

        # Preencher NaN com 0
        df_plot["EQUIPES_VINCULADAS_modelo"] = df_plot[
            "EQUIPES_VINCULADAS_modelo"
        ].fillna(0)
        if "EQUIPES_VINCULADAS_real" in df_plot.columns:
            df_plot["EQUIPES_VINCULADAS_real"] = df_plot[
                "EQUIPES_VINCULADAS_real"
            ].fillna(0)

        # Criar dataframe no formato longo para plotly
        df_melt = pd.melt(
            df_plot,
            id_vars=["cnes_eq_multi"],
            value_vars=["EQUIPES_VINCULADAS_modelo", "EQUIPES_VINCULADAS_real"],
            var_name="Tipo",
            value_name="Quantidade",
        )

        # Renomear os valores para nomes mais legíveis
        df_melt["Tipo"] = df_melt["Tipo"].replace(
            {
                "EQUIPES_VINCULADAS_modelo": "Modelo",
                "EQUIPES_VINCULADAS_real": "Real",
            }
        )

        # Converter cnes_eq_multi para string para melhor visualização
        df_melt["cnes_eq_multi"] = df_melt["cnes_eq_multi"].astype(str)

        # Criar gráfico de barras agrupadas com plotly express
        fig = px.bar(
            df_melt,
            x="cnes_eq_multi",
            y="Quantidade",
            color="Tipo",
            barmode="group",
            color_discrete_map={"Modelo": "blue", "Real": "gray"},
            title="Comparação: Equipes Vinculadas - Modelo vs Real",
            labels={
                "cnes_eq_multi": "CNES Equipe Multi",
                "Quantidade": "Quantidade de Equipes Vinculadas",
                "Tipo": "Tipo",
            },
        )

        # Atualizar layout
        fig.update_layout(
            xaxis_tickangle=-45,
            showlegend=True,
            height=600,
        )

        # Usar função auxiliar para mostrar gráfico de forma robusta
        mostrar_grafico_plotly(fig, "grafico_equipes_vinculadas.html")

    def plota_mapa_comparativo_emulti(self, df_merge):
        """
        Plota mapa comparativo das equipes eMulti mostrando:
        - Fundo coropletico do IVS
        - Pontos pretos escuros se coordenadas do modelo = coordenadas reais
        - Estrela verde para coordenadas do modelo (LATITUDE_FINAL, LONGITUDE_FINAL)
        - Triangulo amarelo para coordenadas reais (LATITUDE, LONGITUDE)
        """
        map, df_b = self.cenario.plota_mapa_basico_setores_censitarios(
            fundo_ivs=True, fundo_cobertura=False
        )

        pontos_plotados = 0
        pontos_iguais = 0
        pontos_modelo = 0
        pontos_real = 0

        for _, row in df_merge.iterrows():
            lat_final = row.get("LATITUDE_FINAL")
            lon_final = row.get("LONGITUDE_FINAL")
            lat_real = row.get("LATITUDE")
            lon_real = row.get("LONGITUDE")

            # Verificar se coordenadas sao validas
            lat_final_valid = pd.notna(lat_final) and pd.notna(lon_final)
            lat_real_valid = pd.notna(lat_real) and pd.notna(lon_real)

            if not lat_final_valid and not lat_real_valid:
                continue

            # Converter para float
            try:
                if lat_final_valid:
                    lat_final = float(lat_final)
                    lon_final = float(lon_final)
                if lat_real_valid:
                    lat_real = float(lat_real)
                    lon_real = float(lon_real)
            except (ValueError, TypeError):
                continue

            # Verificar se coordenadas sao iguais (com tolerancia de 0.0001 graus ~11 metros)
            coordenadas_iguais = False
            if lat_final_valid and lat_real_valid:
                if (
                    abs(lat_final - lat_real) < 0.0001
                    and abs(lon_final - lon_real) < 0.0001
                ):
                    coordenadas_iguais = True

            # Obter informacoes para tooltip
            cnes_eq = row.get("cnes_eq_emulti") or row.get("CO_EQUIPE") or "N/A"
            nome_fantasia = row.get("NO_FANTASIA", "N/A")
            equipas_vinculadas = (
                row.get("EQUIPES_VINCULADAS_modelo")
                or row.get("EQUIPES_VINCULADAS_baseline")
                or "N/A"
            )

            tooltip_text = f"CNES: {cnes_eq}<br>Nome: {nome_fantasia}<br>Equipes: {equipas_vinculadas}"

            if coordenadas_iguais:
                # Coordenadas sao iguais - plotar ponto preto escuro
                if lat_final_valid:
                    folium.CircleMarker(
                        location=[lat_final, lon_final],
                        radius=8,
                        color="white",
                        fillColor="black",
                        fillOpacity=1.0,
                        weight=3,
                        popup=tooltip_text,
                    ).add_to(map)
                    pontos_plotados += 1
                    pontos_iguais += 1
            else:
                # Coordenadas sao diferentes - plotar ambas
                # Marcador verde para coordenadas do modelo
                if lat_final_valid:
                    folium.CircleMarker(
                        location=[lat_final, lon_final],
                        radius=8,
                        color="white",
                        fillColor="#00FF00",
                        fillOpacity=1.0,
                        weight=3,
                        popup=tooltip_text + "<br>Tipo: Modelo",
                    ).add_to(map)
                    pontos_plotados += 1
                    pontos_modelo += 1

                # Marcador laranja para coordenadas reais
                if lat_real_valid:
                    folium.CircleMarker(
                        location=[lat_real, lon_real],
                        radius=8,
                        color="white",
                        fillColor="#FFA500",
                        fillOpacity=1.0,
                        weight=3,
                        popup=tooltip_text + "<br>Tipo: Real",
                    ).add_to(map)
                    pontos_plotados += 1
                    pontos_real += 1

        # Adicionar legenda customizada
        legenda_html = f"""
        <div style="
            position: fixed;
            top: 10px;
            right: 10px;
            width: 220px;
            background-color: white;
            border: 2px solid grey;
            border-radius: 5px;
            padding: 10px;
            font-family: Arial, sans-serif;
            font-size: 12px;
            z-index: 9999;
            box-shadow: 2px 2px 6px rgba(0,0,0,0.3);
        ">
            <h4 style="margin: 0 0 10px 0; font-size: 14px; font-weight: bold;">
                Legenda - Equipes eMulti
            </h4>
            <div style="margin-bottom: 8px;">
                <span style="
                    display: inline-block;
                    width: 16px;
                    height: 16px;
                    background-color: black;
                    border: 2px solid white;
                    border-radius: 50%;
                    margin-right: 8px;
                    vertical-align: middle;
                "></span>
                <span style="vertical-align: middle;">
                    Coordenadas Iguais ({pontos_iguais})
                </span>
            </div>
            <div style="margin-bottom: 8px;">
                <span style="
                    display: inline-block;
                    width: 16px;
                    height: 16px;
                    background-color: #00FF00;
                    border: 2px solid white;
                    border-radius: 50%;
                    margin-right: 8px;
                    vertical-align: middle;
                "></span>
                <span style="vertical-align: middle;">
                    Coordenadas Modelo ({pontos_modelo})
                </span>
            </div>
            <div style="margin-bottom: 0;">
                <span style="
                    display: inline-block;
                    width: 16px;
                    height: 16px;
                    background-color: #FFA500;
                    border: 2px solid white;
                    border-radius: 50%;
                    margin-right: 8px;
                    vertical-align: middle;
                "></span>
                <span style="vertical-align: middle;">
                    Coordenadas Reais ({pontos_real})
                </span>
            </div>
        </div>
        """

        map.get_root().html.add_child(folium.Element(legenda_html))

        print(f"Total de pontos plotados: {pontos_plotados}")
        print(f"  - Coordenadas iguais: {pontos_iguais}")
        print(f"  - Coordenadas modelo: {pontos_modelo}")
        print(f"  - Coordenadas reais: {pontos_real}")

        folium.LayerControl().add_to(map)
        map.save("mapa_comparativo_emulti.html")
        print(f"Mapa salvo com sucesso!")

    def analisa_emulti(self):

        df_modelo = self.cenario.dados_fluxo_emulti.copy()
        df_modelo = self.cenario.dados_fluxo_emulti.copy()
        df_modelo_end = (
            df_modelo.groupby(by="cnes_eq_emulti")
            .agg(
                EQUIPES_VINCULADAS=("cnes_eq_esf", "count"),
                LATITUDE_FINAL=("lat_emulti", "first"),
                LONGITUDE_FINAL=("long_emulti", "first"),
            )
            .reset_index()
        )

        cols_real = [
            "CO_EQUIPE",
            "EQUIPES_VINCULADAS",
            "NO_FANTASIA",
            "CO_CNES",
            "LATITUDE",
            "LONGITUDE",
            "geometry",
        ]
        df_real = self.baseline.df_emulti_reais[cols_real].copy()
        df_merge = df_modelo_end.merge(
            df_real,
            left_on="cnes_eq_emulti",
            right_on="CO_EQUIPE",
            how="outer",
            suffixes=("_modelo", "_baseline"),
        )

        # Preparar dados para o gráfico
        # Usar cnes_eq_emulti ou CO_EQUIPE como identificador (qualquer um que tiver valor)
        self.plota_mapa_comparativo_emulti(df_merge)
        self.plota_comparacao_equipes_emulti(df_merge)

    def analises(self, tamanho_faixa=50):
        self.analisa_emulti()
        self.analises_descritivas()
        self.compara_quantidade_equipes()
        self.plota_comparativo_acessibilidade()
        self.analisa_cobertura_comparativa_por_ivs_2(tamanho_faixa=tamanho_faixa)

        # Proximas analises = Dados de custo e quantitativo de equipes real x criadas!
        # Diferenca de equipes !

        # DF's com resultado: self.df_resultados_esb, self.df_resultados_esf, self.df_resumo_descritivo

        # Comparacao Emulti!
        # Quantidade de equipes ESF Cobertas
        #
        # Histograma da distancia da populacao para mostrar que ficamos mais proximos dos locais vulneraveis
        # Mapa grafico com antes e depois da alocacao das eMulti!
        map_emulti = self.cenario.plota_fluxo_Emulti()
        map_emulti.save("map_fluxo_Emulti_2.html")

    def analises_descritivas(self):
        # populacao total atendida por Esf, EsB,
        # Populacao_Atendida_ESF, Populacao_Atendida_ESB
        # populacao_ajustada_eSF, populacao_ajustada_eSB,
        populacao_total = self.df_merge.Populacao_Total.sum()
        modelo_ESF = self.df_merge.Populacao_Atendida_ESF.sum()
        modelo_ESB = self.df_merge.Populacao_Atendida_ESB.sum()
        real_ESF = self.df_merge.pop_captada_eSF.sum()
        real_ESB = self.df_merge.pop_captada_eSB.sum()

        cobertura_ESF_modelo = round(modelo_ESF / populacao_total, 3)
        cobertura_ESB_modelo = round(modelo_ESB / populacao_total, 3)

        cobertura_ESF_real = round(real_ESF / populacao_total, 3)
        cobertura_ESB_real = round(real_ESB / populacao_total, 3)

        total_modelo = modelo_ESF + modelo_ESB
        total_real = real_ESF + real_ESB
        cobertura_total_modelo = round((total_modelo) / (populacao_total * 2), 3)
        cobertura_total_real = round((total_real) / (populacao_total * 2), 3)

        # Calcular a variação percentual entre total_modelo e total_real
        if total_real != 0:
            variacao_percentual = ((total_modelo - total_real) / total_real) * 100
        else:
            variacao_percentual = float("nan")

        dados_descritivos = {
            "População total": populacao_total,
            "Modelo - População Atendida ESF": modelo_ESF,
            "Modelo - População Atendida ESB": modelo_ESB,
            "Real - População Captada ESF": real_ESF,
            "Real - População Captada ESB": real_ESB,
            "Total Modelo (ESF + ESB)": total_modelo,
            "Total Real (ESF + ESB)": total_real,
            "Cobertura ESF Modelo": cobertura_ESF_modelo,
            "Cobertura ESF Real": cobertura_ESF_real,
            "Cobertura ESB Modelo": cobertura_ESB_modelo,
            "Cobertura ESB Real": cobertura_ESB_real,
            "Cobertura (ESF+ESB) Juntos - Modelo": cobertura_total_modelo,
            "Cobertura (ESF+ESB) Juntos - Real": cobertura_total_real,
        }
        self.df_resumo_descritivo = pd.DataFrame(
            list(dados_descritivos.items()), columns=["Indicador", "Valor"]
        )

        print(f"População total: {populacao_total}")
        print(f"Modelo - População Atendida ESF: {modelo_ESF}")
        print(f"Modelo - População Atendida ESB: {modelo_ESB}")
        print(f"Real - População Captada ESF: {real_ESF}")
        print(f"Real - População Captada ESB: {real_ESB}")
        print(f"Total Modelo (ESF + ESB): {total_modelo}")
        print(f"Total Real (ESF + ESB): {total_real}")
        print(f"Cobertura ESF Modelo: {cobertura_ESF_modelo}")
        print(f"Cobertura ESF Real: {cobertura_ESF_real}")
        print(f"Cobertura ESF Modelo: {cobertura_ESB_modelo}")
        print(f"Cobertura ESF Real: {cobertura_ESB_real}")
        print(
            f"Cobertura ESF e ESB Juntos - Modelo = (Cobertura ESF + Cobertura ESB) / (Pop * 2) = {cobertura_total_modelo} "
        )
        print(
            f"Cobertura ESF e ESB Juntos - Real = (Cobertura ESF + Cobertura ESB) / (Pop * 2) = {cobertura_total_real} "
        )

        # Analise de custos!
        custos_equipe_real = self.baseline.custo_equipes_real.copy()
        custos_equipe_modelo = self.cenario.df_custos.copy()
        custos_fora_grafico = [
            "Contratação ESF",
            "Realocação ESF",
            "Contratação ESB",
            "Realocação ESB",
            "Contratação ENASF",
            "Realocação ENASF",
        ]

        custos_equipe_modelo = custos_equipe_modelo[
            ~custos_equipe_modelo.Tipo_Custo.isin(custos_fora_grafico)
        ]

        # ============================================================================================================
        # FORMATAÇÃO DO DATAFRAME DE CUSTOS DO MODELO
        # ============================================================================================================

        # Assumindo que seu dataframe se chama df_custos_modelo

        # 1. Custos detalhados por tipo de equipe (para gráfico empilhado)
        df_por_equipe = custos_equipe_modelo[
            custos_equipe_modelo["Nivel"].isin(["ESF", "ESB", "ENASF"])
        ].copy()
        df_por_equipe = df_por_equipe[["Tipo_Custo", "Nivel", "Valor_R", "Percentual"]]
        df_por_equipe["Valor_Milhoes"] = df_por_equipe["Valor_R"] / 1e6

        # Transformar para formato wide (para gráfico empilhado)
        df_equipe_pivot = df_por_equipe.pivot(
            index="Tipo_Custo", columns="Nivel", values="Valor_Milhoes"
        )

        # 2. Totais por categoria (ESF, ESB, ENASF, Infraestrutura)
        df_totais_categoria = custos_equipe_modelo[
            custos_equipe_modelo["Nivel"] == "Total por Equipe"
        ].copy()
        df_infraestrutura = custos_equipe_modelo[
            custos_equipe_modelo["Nivel"] == "Total por Categoria"
        ].copy()
        df_totais = pd.concat([df_totais_categoria, df_infraestrutura])
        df_totais = df_totais[["Tipo_Custo", "Valor_R", "Percentual"]].reset_index(
            drop=True
        )
        df_totais["Valor_Milhoes"] = df_totais["Valor_R"] / 1e6

        # 3. Totais por tipo de custo (Contratação, Realocação, Operação)
        df_por_tipo = custos_equipe_modelo[
            custos_equipe_modelo["Nivel"] == "Total por Tipo"
        ].copy()
        df_por_tipo = df_por_tipo[["Tipo_Custo", "Valor_R", "Percentual"]].reset_index(
            drop=True
        )
        df_por_tipo["Valor_Milhoes"] = df_por_tipo["Valor_R"] / 1e6

        # ============================================================================================================
        # FORMATAÇÃO DO DATAFRAME DE CUSTOS REAIS POR EQUIPE
        # ============================================================================================================

        # Assumindo que seu dataframe se chama df_custos_reais
        df_custos_reais_formatado = self.baseline.custo_equipes_real.copy()

        # Renomear colunas para padronização
        df_custos_reais_formatado.columns = [
            "DS_EQUIPE",
            "Qntd_Equipes",
            "Custo_Mensal",
        ]
        df_custos_reais_formatado["Custo_Anual"] = (
            df_custos_reais_formatado["Custo_Mensal"] * 12
        )
        df_custos_reais_formatado["Custo_Anual_Milhoes"] = (
            df_custos_reais_formatado["Custo_Anual"] / 1e6
        )
        df_custos_reais_formatado["Custo_Mensal_Milhoes"] = (
            df_custos_reais_formatado["Custo_Mensal"] / 1e6
        )

        # Calcular percentuais
        total_mensal = df_custos_reais_formatado["Custo_Mensal"].sum()
        df_custos_reais_formatado["Percentual"] = (
            df_custos_reais_formatado["Custo_Mensal"] / total_mensal * 100
        ).round(2)

        # ============================================================================================================
        # GRÁFICOS Comparativos Real x Modelo por Equipes!
        # ============================================================================================================
        def refact__equipes_name_to_plot(eq):
            if "EMULTI" in eq or "ENASF" in eq:
                return "eMulti"
            if "ESB" in eq:
                return "eSB"
            if "ESF" in eq:
                return "eSF"

        # total por equipe
        agg_plot_modelo_total_equipe = (
            df_por_equipe.groupby(by="Nivel")
            .agg(total_por_equie=("Valor_Milhoes", "sum"))
            .reset_index()
        )
        agg_plot_modelo_total_equipe["Tp_custo"] = "Modelo"
        agg_plot_real_total_equipe = df_custos_reais_formatado[
            ["DS_EQUIPE", "Custo_Mensal_Milhoes"]
        ]
        agg_plot_real_total_equipe["Tp_custo"] = "Real"
        agg_plot_real_total_equipe = agg_plot_real_total_equipe.rename(
            columns={"DS_EQUIPE": "Equipe", "Custo_Mensal_Milhoes": "Custo Total"}
        )
        agg_plot_modelo_total_equipe = agg_plot_modelo_total_equipe.rename(
            columns={"Nivel": "Equipe", "total_por_equie": "Custo Total"}
        )
        df_plot_comp_custos_total = pd.concat(
            [agg_plot_modelo_total_equipe, agg_plot_real_total_equipe]
        )
        df_plot_comp_custos_total["Equipe"] = df_plot_comp_custos_total["Equipe"].apply(
            refact__equipes_name_to_plot
        )

        # custo total por equipe!
        custo_total_equipes_modelo_dict = {
            "Equipe": "Custo Total de Equipes",
            "Custo Total": round(
                df_plot_comp_custos_total[
                    df_plot_comp_custos_total.Tp_custo == "Modelo"
                ]["Custo Total"].sum(),
                3,
            ),
            "Tp_custo": "Modelo",
        }

        custo_total_equipes_real_dict = {
            "Equipe": "Custo Total de Equipes",
            "Custo Total": round(
                df_plot_comp_custos_total[df_plot_comp_custos_total.Tp_custo == "Real"][
                    "Custo Total"
                ].sum(),
                3,
            ),
            "Tp_custo": "Real",
        }

        df_totais_custo = pd.DataFrame(
            [custo_total_equipes_modelo_dict, custo_total_equipes_real_dict]
        )

        df_plot_comp_custos_total_equipes = pd.concat(
            [df_plot_comp_custos_total, df_totais_custo], ignore_index=True
        )

        # ============================================================================================================
        # GRÁFICOS Comparativos Real x Modelo geral: Custo de Equipes, Custo Fixo, Custo Variavel, Custo Realocacao,
        # ============================================================================================================
        # Calcular variáveis individuais
        custo_fixo_real = round(self.baseline.custo_fixo_real / 1000000, 3)
        custo_fixo_equipes_real = df_custos_reais_formatado.Custo_Mensal_Milhoes.sum()
        # custo_realocacao_equipes_real = 0
        # custo_contratacao_equipes_real = 0
        custo_abertura_unidades_real = 0
        custo_total_real = round(self.baseline.custo_total / 1000000, 3)

        custo_fixo_modelo = round(
            self.cenario.df_custos[
                self.cenario.df_custos.Tipo_Custo == "Custo Fixo UBS"
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )
        custo_fixo_equipes_modelo = round(
            self.cenario.df_custos[
                (
                    (self.cenario.df_custos.Nivel == "Total por Tipo")
                    & (self.cenario.df_custos.Tipo_Custo == "Total Operação")
                )
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )
        """
        custo_realocacao_equipes_modelo = round(
            self.cenario.df_custos[
                (
                    (self.cenario.df_custos.Nivel == "Total por Tipo")
                    & (self.cenario.df_custos.Tipo_Custo == "Total Realocação")
                )
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )
        custo_contratacao_equipes_modelo = round(
            self.cenario.df_custos[
                (
                    (self.cenario.df_custos.Nivel == "Total por Tipo")
                    & (self.cenario.df_custos.Tipo_Custo == "Total Contratação")
                )
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )
        
        
        """

        custo_abertura_unidades_modelo = round(
            self.cenario.df_custos[
                self.cenario.df_custos.Tipo_Custo == "Abertura UBS"
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )
        custo_total_modelo = round(
            self.cenario.df_custos[
                self.cenario.df_custos.Tipo_Custo == "CUSTO TOTAL"
            ].Valor_R.iloc[0]
            / 1000000,
            3,
        )

        # Passar tudo para um dataframe "longo" conforme solicitado
        # Tipo de custo será o nome base sem o sufixo _real/_modelo
        # Tp_Custo será "real" ou "modelo"

        dados_compilados = [
            {
                "tipo_custo": "custo_fixo",
                "valor": custo_fixo_real,
                "Tp_Custo": "real",
            },
            {
                "tipo_custo": "custo_fixo_equipes",
                "valor": custo_fixo_equipes_real,
                "Tp_Custo": "real",
            },
            # {
            # "tipo_custo": "custo_realocacao_equipes",
            # "valor": custo_realocacao_equipes_real,
            # "Tp_Custo": "real",
            # },
            # {
            #  "tipo_custo": "custo_contratacao_equipes",
            #  "valor": custo_contratacao_equipes_real,
            # "Tp_Custo": "real",
            # },
            {
                "tipo_custo": "custo_abertura_unidades",
                "valor": custo_abertura_unidades_real,
                "Tp_Custo": "real",
            },
            {
                "tipo_custo": "custo_total",
                "valor": custo_total_real,
                "Tp_Custo": "real",
            },
            {
                "tipo_custo": "custo_fixo",
                "valor": custo_fixo_modelo,
                "Tp_Custo": "modelo",
            },
            {
                "tipo_custo": "custo_fixo_equipes",
                "valor": custo_fixo_equipes_modelo,
                "Tp_Custo": "modelo",
            },
            # {
            #  "tipo_custo": "custo_realocacao_equipes",
            # "valor": custo_realocacao_equipes_modelo,
            # "Tp_Custo": "modelo",
            # },
            # {
            # "tipo_custo": "custo_contratacao_equipes",
            # "valor": custo_contratacao_equipes_modelo,
            #  "Tp_Custo": "modelo",
            # },
            {
                "tipo_custo": "custo_abertura_unidades",
                "valor": custo_abertura_unidades_modelo,
                "Tp_Custo": "modelo",
            },
            {
                "tipo_custo": "custo_total",
                "valor": custo_total_modelo,
                "Tp_Custo": "modelo",
            },
        ]

        df_resumo_custos_compilado = pd.DataFrame(dados_compilados)

        # ============================================================================================================
        # Extratificacao custos Equipes - Só Modelo!
        # ============================================================================================================

        df_plot = self.cenario.df_custos[
            self.cenario.df_custos.Nivel.isin(["ESF", "ESB", "ENASF"])
        ].copy()
        df_plot["Equipe"] = df_plot.Nivel.apply(refact__equipes_name_to_plot)
        df_plot["custo_total"] = round(df_plot.Valor_R / 1000000, 3)
        df_plot_end = df_plot[["Equipe", "custo_total", "Tipo_Custo"]]

        # Criar gráfico com 3 subplots
        self.cria_grafico_custos_comparativo(
            df_plot_comp_custos_total_equipes,
            df_resumo_custos_compilado,
            df_plot_end,
        )

    def cria_grafico_custos_comparativo(
        self,
        df_plot_comp_custos_total_equipes,
        df_resumo_custos_compilado,
        df_plot_end,
    ):
        """
        Cria gráfico com 3 subplots comparando custos entre modelo e real
        """
        import plotly.graph_objects as go
        from plotly.subplots import make_subplots

        # Definir cores consistentes
        cores = {
            "real": "#1f77b4",  # Azul
            "modelo": "#7f7f7f",  # Cinza
            "Real": "#1f77b4",  # Azul (com R maiúsculo)
            "Modelo": "#7f7f7f",  # Cinza (com M maiúsculo)
        }

        # Criar subplots: 1 grande em cima, 2 menores embaixo
        fig = make_subplots(
            rows=2,
            cols=1,
            subplot_titles=(
                "Comparação de Custos por Categoria (Real vs Modelo)",
                "Comparação de Custos por Equipe (Real vs Modelo)",
            ),
            specs=[
                [{"type": "bar"}],
                [{"type": "bar"}],
            ],
            vertical_spacing=0.25,
            horizontal_spacing=0.12,
        )

        # ============================================================================================================
        # GRÁFICO 1: df_resumo_custos_compilado (maior, em cima)
        # ============================================================================================================

        # Filtrar dados por tipo de custo
        for tp_custo in df_resumo_custos_compilado["Tp_Custo"].unique():
            df_filtrado = df_resumo_custos_compilado[
                df_resumo_custos_compilado["Tp_Custo"] == tp_custo
            ]

            fig.add_trace(
                go.Bar(
                    x=df_filtrado["tipo_custo"],
                    y=df_filtrado["valor"],
                    name=f"Custos {tp_custo.title()}",
                    marker_color=cores[tp_custo],
                    text=df_filtrado["valor"].apply(lambda x: f"{x:.3f}"),
                    textposition="outside",
                    showlegend=True,
                ),
                row=1,
                col=1,
            )

        # ============================================================================================================
        # GRÁFICO 2: df_plot_comp_custos_total_equipes (esquerda embaixo)
        # ============================================================================================================

        for tp_custo in df_plot_comp_custos_total_equipes["Tp_custo"].unique():
            df_filtrado = df_plot_comp_custos_total_equipes[
                df_plot_comp_custos_total_equipes["Tp_custo"] == tp_custo
            ]

            fig.add_trace(
                go.Bar(
                    x=df_filtrado["Equipe"],
                    y=df_filtrado["Custo Total"],
                    name=f"Equipes {tp_custo}",
                    marker_color=cores[tp_custo],
                    text=df_filtrado["Custo Total"].apply(lambda x: f"{x:.3f}"),
                    textposition="outside",
                    showlegend=False,
                ),
                row=2,
                col=1,
            )

        # ============================================================================================================
        # GRÁFICO 3: df_plot_end (direita embaixo)
        # ============================================================================================================

        # Para este gráfico, vamos usar cores diferentes para cada tipo de custo
        # cores_tipo_custo = {
        #     "Contratação ESF": "#ff7f0e",  # Laranja
        #     "Realocação ESF": "#2ca02c",  # Verde
        #     "Operação ESF": "#d62728",  # Vermelho
        #     "Contratação ESB": "#9467bd",  # Roxo
        #     "Realocação ESB": "#8c564b",  # Marrom
        #     "Operação ESB": "#e377c2",  # Rosa
        #     "Contratação ENASF": "#7f7f7f",  # Cinza
        #     "Realocação ENASF": "#bcbd22",  # Verde amarelado
        #     "Operação ENASF": "#17becf",  # Ciano
        # }

        # for equipe in df_plot_end["Equipe"].unique():
        #     df_equipe = df_plot_end[df_plot_end["Equipe"] == equipe]

        #     for _, row in df_equipe.iterrows():
        #         tipo_custo = row["Tipo_Custo"]
        #         cor = cores_tipo_custo.get(tipo_custo, "#7f7f7f")

        #         fig.add_trace(
        #             go.Bar(
        #                 x=[equipe],
        #                 y=[row["custo_total"]],
        #                 name=tipo_custo,
        #                 marker_color=cor,
        #                 text=f"{row['custo_total']:.3f}",
        #                 textposition="outside",
        #                 showlegend=False,
        #                 legendgroup=equipe,
        #             ),
        #             row=2,
        #             col=2,
        #         )

        # ============================================================================================================
        # CONFIGURAÇÃO DO LAYOUT
        # ============================================================================================================

        fig.update_layout(
            height=1000,
            width=1200,
            title_text="Análise Comparativa de Custos: Real vs Modelo",
            title_x=0.5,
            title_font_size=16,
            showlegend=True,
            paper_bgcolor="#ffffff",
            plot_bgcolor="#ffffff",
            margin=dict(t=90, b=90, l=80, r=40),
            legend=dict(
                orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5
            ),
            barmode="group",
            bargap=0.2,
        )

        # Configurar eixos
        fig.update_xaxes(title_text="Tipo de Custo", row=1, col=1)
        fig.update_xaxes(title_text="Equipe", row=2, col=1)
        # fig.update_xaxes(title_text="Equipe", row=2, col=2)

        fig.update_yaxes(title_text="Custo (Milhões R$)", row=1, col=1)
        fig.update_yaxes(title_text="Custo (Milhões R$)", row=2, col=1)
        # fig.update_yaxes(title_text="Custo (Milhões R$)", row=2, col=2)

        # Rotacionar labels do eixo x para melhor legibilidade
        fig.update_xaxes(tickangle=45, row=1, col=1)
        fig.update_xaxes(tickangle=45, row=2, col=1)
        # fig.update_xaxes(tickangle=45, srow=2, col=2)

        # Ajustes globais de traços
        fig.update_traces(cliponaxis=False)

        # Salvar o gráfico
        fig.write_html("analise_custos_completa.html")
        fig.write_image("analise_custos_completa.png", width=1200, height=1000)

        print("Gráfico de análise de custos criado e salvo!")
        # return fig

    def analisa_cobertura_comparativa_por_ivs_2(self, tamanho_faixa=20):

        print("LOGGING: INICIANDO ANÁLISE COMPARATIVA DE COBERTURA POR FAIXAS DE IVS")

        # Trabalhar com cópia do dataframe
        df = self.df_merge.copy()

        # Verificar colunas necessárias
        colunas_necessarias = {
            "ESF": ["pop_captada_eSF", "Populacao_Atendida_ESF"],
            "ESB": ["pop_captada_eSB", "Populacao_Atendida_ESB"],
        }

        for tipo, cols in colunas_necessarias.items():
            for col in cols:
                if col not in df.columns:
                    print(f"ERRO: Coluna '{col}' não encontrada para {tipo}!")
                    return None, None

        total_setores = len(df)
        num_faixas = int(np.ceil(total_setores / tamanho_faixa))

        # Dicionário para armazenar resultados
        resultados_dict = {"ESF": [], "ESB": []}

        # Processar cada tipo de equipe
        for tipo_equipe in ["ESF", "ESB"]:
            col_captada = colunas_necessarias[tipo_equipe][0]
            col_atendida = colunas_necessarias[tipo_equipe][1]

            print(f"\n{'='*60}")
            print(f"ANÁLISE {tipo_equipe}")
            print(f"{'='*60}")

            for i in range(num_faixas):
                inicio_faixa = i * tamanho_faixa + 1
                fim_faixa = min((i + 1) * tamanho_faixa, total_setores)

                # Filtrar setores nesta faixa
                setores_faixa = df[
                    (df["Posicao_Ranking_IVS"] >= inicio_faixa)
                    & (df["Posicao_Ranking_IVS"] <= fim_faixa)
                ]

                # Calcular métricas
                total_na_faixa = len(setores_faixa)
                pop_captada_total = setores_faixa[col_captada].sum()
                pop_atendida_total = setores_faixa[col_atendida].sum()
                diferenca = pop_atendida_total - pop_captada_total
                percentual_atendimento = (
                    (pop_atendida_total / pop_captada_total * 100)
                    if pop_captada_total > 0
                    else 0
                )

                # Setores com cobertura
                setores_com_captacao = (setores_faixa[col_captada] > 0).sum()
                setores_com_atendimento = (setores_faixa[col_atendida] > 0).sum()

                # IVS médio
                ivs_medio = setores_faixa["IVS"].mean()

                nivel_criticidade = (
                    "Muito Alto"
                    if inicio_faixa <= 20
                    else (
                        "Alto"
                        if inicio_faixa <= 40
                        else (
                            "Médio"
                            if inicio_faixa <= 60
                            else "Baixo" if inicio_faixa <= 80 else "Muito Baixo"
                        )
                    )
                )

                resultados_dict[tipo_equipe].append(
                    {
                        "Faixa": f"{inicio_faixa}-{fim_faixa}",
                        "Inicio_Faixa": inicio_faixa,
                        "Fim_Faixa": fim_faixa,
                        "Total_Setores": total_na_faixa,
                        "Pop_Captada": pop_captada_total,
                        "Pop_Atendida": pop_atendida_total,
                        "Diferenca": diferenca,
                        "Percentual_Atendimento": percentual_atendimento,
                        "Setores_Com_Captacao": setores_com_captacao,
                        "Setores_Com_Atendimento": setores_com_atendimento,
                        "IVS_Medio": ivs_medio,
                        "Nivel_Criticidade": nivel_criticidade,
                    }
                )

                print(f"Faixa {inicio_faixa}-{fim_faixa} ({nivel_criticidade}):")
                print(
                    f"  Pop Captada: {pop_captada_total:,.0f} | Pop Atendida: {pop_atendida_total:,.0f}"
                )
                print(f"  Diferença: {diferenca:+,.0f} ({percentual_atendimento:.1f}%)")
                print(
                    f"  Setores: {setores_com_atendimento}/{setores_com_captacao} com atendimento"
                )

        # Converter para DataFrames
        self.df_resultados_esf = pd.DataFrame(resultados_dict["ESF"])
        self.df_resultados_esb = pd.DataFrame(resultados_dict["ESB"])

        # Criar subplots com Plotly
        fig = make_subplots(
            rows=3,
            cols=2,
            subplot_titles=(
                "ESF - Atendimento Baseline vs Atendida Atendimento Modelo",
                "ESB - Atendimento Baseline vs Atendida Atendimento Modelo",
                "ESF - Diferença (Baseline - Modelo)",
                "ESB - Diferença (Baseline - Modelo)",
            ),
            vertical_spacing=0.12,
            horizontal_spacing=0.1,
        )

        # Cores consistentes
        cor_captada = "#4682B4"
        cor_atendida = "#32CD32"
        cor_deficit = "#DC143C"
        cor_superavit = "#32CD32"

        # --- GRÁFICO 1: ESF - Captada vs Atendida ---
        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esf["Faixa"],
                y=self.df_resultados_esf["Pop_Captada"],
                name="Baseline",
                marker_color=cor_captada,
                text=self.df_resultados_esf["Pop_Captada"].apply(lambda x: f"{x:,.0f}"),
                textposition="outside",
                legendgroup="captada",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esf["Faixa"],
                y=self.df_resultados_esf["Pop_Atendida"],
                name="Modelo",
                marker_color=cor_atendida,
                text=self.df_resultados_esf["Pop_Atendida"].apply(
                    lambda x: f"{x:,.0f}"
                ),
                textposition="outside",
                legendgroup="atendida",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        # --- GRÁFICO 2: ESB - Captada vs Atendida ---
        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esb["Faixa"],
                y=self.df_resultados_esb["Pop_Captada"],
                name="Baseline",
                marker_color=cor_captada,
                text=self.df_resultados_esb["Pop_Captada"].apply(lambda x: f"{x:,.0f}"),
                textposition="outside",
                legendgroup="captada",
                showlegend=False,
            ),
            row=1,
            col=2,
        )

        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esb["Faixa"],
                y=self.df_resultados_esb["Pop_Atendida"],
                name="Modelo",
                marker_color=cor_atendida,
                text=self.df_resultados_esb["Pop_Atendida"].apply(
                    lambda x: f"{x:,.0f}"
                ),
                textposition="outside",
                legendgroup="atendida",
                showlegend=False,
            ),
            row=1,
            col=2,
        )

        # --- GRÁFICO 3: ESF - Diferença ---
        cores_diff_esf = [
            cor_superavit if x >= 0 else cor_deficit
            for x in self.df_resultados_esf["Diferenca"]
        ]
        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esf["Faixa"],
                y=self.df_resultados_esf["Diferenca"],
                name="Diferença",
                marker_color=cores_diff_esf,
                text=self.df_resultados_esf["Diferenca"].apply(lambda x: f"{x:+,.0f}"),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=1,
        )

        # Linha zero
        fig.add_hline(
            y=0, line_dash="dash", line_color="black", opacity=0.5, row=2, col=1
        )

        # --- GRÁFICO 4: ESB - Diferença ---
        cores_diff_esb = [
            cor_superavit if x >= 0 else cor_deficit
            for x in self.df_resultados_esb["Diferenca"]
        ]
        fig.add_trace(
            go.Bar(
                x=self.df_resultados_esb["Faixa"],
                y=self.df_resultados_esb["Diferenca"],
                name="Diferença",
                marker_color=cores_diff_esb,
                text=self.df_resultados_esb["Diferenca"].apply(lambda x: f"{x:+,.0f}"),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=2,
        )

        fig.add_hline(
            y=0, line_dash="dash", line_color="black", opacity=0.5, row=2, col=2
        )

        # --- GRÁFICO 5: ESF - Percentual ---
        # Atualizar layout
        fig.update_xaxes(
            title_text="Faixas de Ranking De Vulnerabilidade (1 = Mais Vulnerável)",
            row=3,
            col=1,
        )
        fig.update_xaxes(
            title_text="Faixas de Ranking De Vulnerabilidade (1 = Mais Vulnerável)",
            row=3,
            col=2,
        )

        fig.update_yaxes(title_text="População", row=1, col=1)
        fig.update_yaxes(title_text="População", row=1, col=2)
        fig.update_yaxes(title_text="Diferença (pessoas)", row=2, col=1)
        fig.update_yaxes(title_text="Diferença (pessoas)", row=2, col=2)
        fig.update_yaxes(title_text="Percentual (%)", row=3, col=1)
        fig.update_yaxes(title_text="Percentual (%)", row=3, col=2)

        fig.update_layout(
            height=1200,
            width=1400,
            title_text="Análise Comparativa: Baseline vs Atendimento Modelo por Faixas de Ranking de Viabilidade (TopSis)",
            title_x=0.5,
            showlegend=True,
            legend=dict(
                orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5
            ),
            barmode="group",
        )

        # Resumo final
        print("\n" + "=" * 80)
        print("RESUMO COMPARATIVO GERAL")
        print("=" * 80)

        # Salvar os dados do resumo comparativo em um DataFrame
        resumo_comparativo = []

        for tipo_equipe in ["ESF", "ESB"]:
            df_res = resultados_dict[tipo_equipe]
            total_captada = sum([r["Pop_Captada"] for r in df_res])
            total_atendida = sum([r["Pop_Atendida"] for r in df_res])
            diff_total = total_atendida - total_captada
            percentual = (
                (total_atendida / total_captada * 100) if total_captada > 0 else 0
            )

            print(f"\n{tipo_equipe}:")
            print(f"  Total Captado: {total_captada:,.0f} pessoas")
            print(f"  Total Atendido: {total_atendida:,.0f} pessoas")
            print(f"  Diferença: {diff_total:+,.0f} ({percentual:.1f}%)")

            resumo_dados = {
                "Tipo_Equipe": tipo_equipe,
                "Total_Captado": total_captada,
                "Total_Atendido": total_atendida,
                "Diferenca_Total": diff_total,
                "Percentual_Atendido_sobre_Captado": percentual,
                "Top_Faixa_Captado": None,
                "Top_Faixa_Atendido": None,
                "Top_Faixa_Diferenca": None,
                "Faixa_Top": None,
            }

            # Top mais vulneráveis
            if len(df_res) > 0:
                top_capt = df_res[0]["Pop_Captada"]
                top_atend = df_res[0]["Pop_Atendida"]
                top_diff = top_atend - top_capt
                print(f"  Top {tamanho_faixa} mais vulneráveis:")
                print(
                    f"    Captado: {top_capt:,.0f} | Atendido: {top_atend:,.0f} | "
                    f"Diferença: {top_diff:+,.0f}"
                )
                resumo_dados.update(
                    {
                        "Top_Faixa_Captado": top_capt,
                        "Top_Faixa_Atendido": top_atend,
                        "Top_Faixa_Diferenca": top_diff,
                        "Faixa_Top": tamanho_faixa,
                    }
                )
            resumo_comparativo.append(resumo_dados)

        self.df_resumo_comparativo_por_faixa = pd.DataFrame(resumo_comparativo)

        # fig.show()
        fig.write_html("comparacao_cobertura_custos_reais.html")
        fig.write_image("comparacao_cobertura.png", width=1400, height=1200)

        # return fig, {"ESF": df_resultados_esf, "ESB": df_resultados_esb}

    def compara_fluxo_emulti(self):
        # TODO: Implementar comparação de fluxo emulti
        pass


def main():
    path_cenario = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_raio_1.5_KM_CUSTOS_FINAL_CAPACITADO_REST_CRIACAO_v4.xlsx"
    # path_cenario = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_raio_8_KM_CUSTOS_FINAL.xlsx"
    path_baseline = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\resultados_Baseline_DataSus_Cobertura_por_equipes_v2.xlsx"
    # analise_cen = AnaliseCenario(path_cenario=path_cenario)
    # map, _ = analise_cen.plota_fluxo_pacientes(fundo_ivs=False)
    # basic_map.save("map_fluxo_Emulti_2.html")
    # map_emulti = analise_cen.plota_fluxo_Emulti()
    # map_fluxo_pacientes, _ = analise_cen.plota_fluxo_pacientes_secundario_terciario()

    # map.save("map_fluxo_pacientes_10.html")

    comparador_cenario = ComparaResultadoBaseline(
        path_cenario=path_cenario, path_baseline=path_baseline
    )
    comparador_cenario.analises(tamanho_faixa=50)
    # comparador_cenario.fluxo_emulti()

    # Salvar gráfico
    # figura.savefig("comparacao_cobertura_esf_esb.png", dpi=300, bbox_inches="tight")

    # Ver dados detalhados
    # print(df_esf)
    # print(df_esb)
    # analise_baseline = AnaliseBaselineMapaSus(path_baseline)

    # analise_cen = AnaliseCenario(path_cenario=path_cenario)
    # map, _ = analise_cen.plota_fluxo_pacientes(fundo_ivs=False)
    # basic_map.save("map_fluxo_Emulti_2.html")
    # map_emulti = analise_cen.plota_fluxo_Emulti()
    # map_fluxo_pacientes, _ = analise_cen.plota_fluxo_pacientes_secundario_terciario()

    # map.save("map_fluxo_pacientes_10.html")
    # analise_cen.analise_descritiva_cenario()


# map = self.plota_mapa_base_setores(cen=cen, incluir_ubs=True)
if __name__ == "__main__":
    main()
