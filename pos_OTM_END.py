import pandas as pd
import numpy as np
import folium
from folium.plugins import (
    MarkerCluster,
    MeasureControl,
    Draw,
    OverlappingMarkerSpiderfier,
)
import geopandas as gpd
import seaborn as sns
import matplotlib.pyplot as plt
import plotly.express as px

"""
classe que recebe dois arquivos excel
1 -  baseline 

2 - resultados otimizacao

"""


# TODO: Ja pensar em multiplos resultados com baseline!
class posOTMFinal:
    def __init__(self, path_baseline, dicts_resultados_otimizacao):
        self.baseline = pd.read_excel(path_baseline)
        self.dfs_otm_cobertura = dict()
        self.dfs_otm_fluxo_equipes = dict()
        self.dfs_otm_custos = dict()
        for cen, path in dicts_resultados_otimizacao.items():
            self.dfs_otm_cobertura[cen] = pd.read_excel(path, sheet_name="Sheet1")
            self.dfs_otm_fluxo_equipes[cen] = pd.read_excel(
                path_resultados_otimizacao_1, sheet_name="Fluxo_Equipes"
            )
            self.dfs_otm_custos[cen] = pd.read_excel(
                path_resultados_otimizacao_1, sheet_name="Custos"
            )

        self.merge_dados_cobertura()
        self.lat_long_contagem = (-19.9321, -44.0539)

    def calcula_cobertura_total(self):

        self.coberturas_totais = dict()
        self.coberturas_totais["baseline"] = round(
            (self.baseline.populacao_ajustada.sum() / self.baseline.populacao.sum())
            * 100,
            2,
        )
        print(f"Cobertura baseline: {self.coberturas_totais['baseline']}%")
        for cen in self.dfs_otm_cobertura.keys():
            cobertura_modelo = round(
                (
                    self.dfs_otm_cobertura[cen].Populacao_Atendida.sum()
                    / self.dfs_otm_cobertura[cen].Populacao_Total.sum()
                )
                * 100,
                2,
            )
            self.coberturas_totais[cen] = cobertura_modelo
            print(f"Cobertura {cen}: {cobertura_modelo}%")

    def quantidade_setores_com_maior_cobertura(self):
        cols_compare = [
            i for i in self.df_merge if "Populacao_Atendida_Resultados" in i
        ]
        col_compare_baseline = "populacao_ajustada"
        self.quantidade_setores_modelo_ganha_baseline = dict()
        for cl in cols_compare:
            result_compare = (
                self.df_merge[cl] < self.df_merge[col_compare_baseline]
            ).value_counts()  # True significa que modelo é menor - logo precisamos do false!
            self.quantidade_setores_modelo_ganha_baseline[cl] = result_compare[False]
            print(
                f"Modelo {cl} foi igual ou semelhante ao baseline em {result_compare[False]} e foi pior em {result_compare[True]}"
            )

    def merge_dados_cobertura(self):
        """
        mergeia df cobertura com df baseline para conseguir comparar as coberturas por setor censitario
        """
        df_baseline = self.baseline[
            ["id_setor", "populacao_ajustada", "populacao", "geometry"]
        ].copy()
        for cen, df in self.dfs_otm_cobertura.items():
            # TODO: Nao era melhor trazer os dados do baseline para cada cenario ?
            df["id_setor"] = df.Setor.apply(lambda x: np.int64(x[:-1]))
            df_aux = df.copy()
            df_aux.rename(
                columns={i: f"{i}_{cen}" for i in df_aux.columns}, inplace=True
            )
            df_baseline = df_baseline.merge(
                df_aux, left_on="id_setor", right_on=f"id_setor_{cen}", how="left"
            )
            print(f"Shape do df_baseline pos merge = {df_baseline.shape}")
        self.df_merge = df_baseline.copy()

    def plota_mapa_cobertura_OTM(self, cen):
        cols_base = ["id_setor", "geometry"]
        cols_plot = [i for i in self.df_merge.columns if cen in i or i in cols_base]
        resultado = self.df_merge[cols_plot].copy()
        if not isinstance(resultado, gpd.GeoDataFrame):
            resultado = gpd.GeoDataFrame(
                resultado,
                geometry=(
                    gpd.GeoSeries.from_wkt(resultado["geometry"])
                    if resultado["geometry"].dtype == "O"
                    else resultado["geometry"]
                ),
            )

        map = folium.Map(
            location=[self.lat_long_contagem[0], self.lat_long_contagem[1]],
            tiles="cartodbpositron",
            control_scale=True,
            prefer_canvas=True,
            zoom_start=11,
        )
        # Pane para garantir UBS por cima de tudo
        folium.map.CustomPane(name="ubs_top", z_index=650).add_to(map)
        # Panes intermediários para pontos dos setores e linhas de ligação
        folium.map.CustomPane(name="demanda_mid", z_index=635).add_to(map)
        folium.map.CustomPane(name="links_mid", z_index=640).add_to(map)
        # Camadas para visualização
        ubs_layer = folium.FeatureGroup(name="Unidades de saúde")
        demanda_layer = folium.FeatureGroup(name="Setores (pontos)")
        ligacao_layer = folium.FeatureGroup(name="Ligação Demanda → UBS")
        # camadas serão adicionadas ao mapa mais adiante para garantir ordem visual
        for index, cnes in resultado.iterrows():
            try:
                # Coordenadas UBS (aceita variações de nome)
                lat_ubs = cnes.get(f"Lat_UBS_{cen}")
                lon_ubs = cnes.get(f"Lon_UBS_{cen}")
                if pd.isna(lon_ubs):
                    lon_ubs = cnes.get(f"Long_UBS_{cen}")

                # Coordenadas demanda (aceita variações de nome)
                lat_dem = cnes.get(f"Lat_Demanda_{cen}")
                lon_dem = cnes.get(f"Lon_Demanda_{cen}")
                if pd.isna(lon_dem):
                    lon_dem = cnes.get(f"Long_Demanda_{cen}")

                # UBS como ponto pequeno (preto) no topo
                if pd.notna(lat_ubs) and pd.notna(lon_ubs):
                    folium.CircleMarker(
                        location=[lat_ubs, lon_ubs],
                        radius=4,
                        color="#000000",
                        fill=True,
                        fill_color="#000000",
                        fill_opacity=1.0,
                        opacity=1.0,
                        weight=0,
                        pane="ubs_top",
                        tooltip=cnes.get(f"UBS_Alocada_{cen}"),
                    ).add_to(ubs_layer)

                # Ponto para centro do setor censitário (bem pequeno)
                if pd.notna(lat_dem) and pd.notna(lon_dem):
                    folium.CircleMarker(
                        location=[lat_dem, lon_dem],
                        radius=2,
                        color="#1f77b4",
                        fill=True,
                        fill_color="#1f77b4",
                        fill_opacity=0.9,
                        opacity=0.9,
                        weight=0,
                        pane="demanda_mid",
                    ).add_to(demanda_layer)

                # Linha ligando demanda → UBS
                if (
                    pd.notna(lat_dem)
                    and pd.notna(lon_dem)
                    and pd.notna(lat_ubs)
                    and pd.notna(lon_ubs)
                ):
                    folium.PolyLine(
                        locations=[[lat_dem, lon_dem], [lat_ubs, lon_ubs]],
                        color="#2c7fb8",  # azul mais visível
                        weight=1.6,
                        opacity=0.8,
                        dash_array="3,2",
                        pane="links_mid",
                    ).add_to(ligacao_layer)
            except Exception as e:
                print(f"Erro ao processar linha {index}: {e}")
                continue

        # cria os estabelecimentos
        resultado_choropleth = resultado.copy()
        resultado_choropleth = resultado_choropleth.reset_index()
        resultado_choropleth["id_setor"] = resultado_choropleth.index
        # O formato atual está incorreto: falta uma vírgula entre f"UBS_Alocada_{cen}" e f"IVS_{cen}",
        # O correto é:
        cols_indices_to_plot = [
            f"Populacao_Total_{cen}",
            f"Populacao_Atendida_{cen}",
            f"UBS_Alocada_{cen}",
            f"IVS_{cen}",
        ]

        # Corrige o erro adicionando a coluna 'id' ao DataFrame
        resultado_choropleth["id"] = resultado_choropleth.index

        # Certifique-se de que o GeoDataFrame tem um CRS definido (WGS84)
        if not resultado_choropleth.crs:
            resultado_choropleth.set_crs(epsg=4326, inplace=True)
        elif resultado_choropleth.crs.to_epsg() != 4326:
            resultado_choropleth = resultado_choropleth.to_crs(epsg=4326)

        folium.Choropleth(
            geo_data=resultado_choropleth,
            name=f"Populacao_Atendida_{cen}",
            data=resultado_choropleth,
            columns=["id", f"Populacao_Atendida_{cen}"],
            key_on="feature.id",
            fill_color="Reds",  # Mudando para vermelho para maior contraste
            fill_opacity=0.9,  # Aumentando opacidade
            line_opacity=0.7,  # Aumentando opacidade das bordas
            line_color="black",
            line_weight=1.0,  # Aumentando espessura das bordas
            smooth_factor=1.0,  # Reduzindo suavização para manter detalhes
            nan_fill_color="LightGray",  # Mudando cor para valores nulos
            legend_name=f"Cobertura Populacao {cen}",
            # bins=bins,  # Usando bins personalizados
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

        # Adiciona as camadas na ordem correta (links, demanda e por fim UBS)
        ligacao_layer.add_to(map)
        demanda_layer.add_to(map)
        # Adiciona a camada das UBS por último para garantir que fique por cima
        ubs_layer.add_to(map)

        # Add the marker cluster to the map

        folium.LayerControl().add_to(map)
        return map

    def plota_mapa_cobertura_otimizacao(self):
        b = 0

    def plota_mapa_fluxo_equipes(self, cen):
        df = self.dfs_otm_fluxo_equipes[cen]
        df = df[(df.Total_Equipes > 0) | (df.Tipo_UBS == "Real")].reset_index()
        # 1) Distribuição geral (hist + KDE)
        plt.figure(figsize=(7, 4))
        sns.histplot(df["Valor_Variavel_Fluxo"], bins=30, kde=True, color="#1f77b4")
        plt.axvline(0, color="black", lw=1)
        plt.title("Distribuição de Valor_Variavel_Fluxo")
        plt.xlabel("Valor_Variavel_Fluxo")
        plt.ylabel("Frequência")
        plt.tight_layout()
        plt.show()

        # 2) Comparação por tipo (box + pontos)
        plt.figure(figsize=(7, 4))
        sns.boxplot(data=df, x="Tipo_UBS", y="Valor_Variavel_Fluxo", whis=1.5)
        sns.stripplot(
            data=df, x="Tipo_UBS", y="Valor_Variavel_Fluxo", color="0.25", alpha=0.5
        )
        plt.axhline(0, color="black", lw=1)
        plt.title("Fluxo por Tipo de UBS")
        plt.tight_layout()
        plt.show()

        # 3) Relação com equipes (scatter interativo)
        fig = px.scatter(
            df,
            x="Total_Equipes",
            y="Valor_Variavel_Fluxo",
            color="Tipo_UBS",
            size="Quantidade_Equipes_CNES",
            hover_data=["UBS", "Quantidade_Equipes_CNES", "Total_Equipes"],
            trendline="ols",
            template="plotly_white",
            title="Fluxo vs Total de Equipes (tamanho = Quantidade_Equipes_CNES)",
        )
        fig.add_hline(y=0, line_color="black")
        fig.show()

        # 4) Top/bottom (barra divergente ordenada)
        topn = 100
        df2 = df[["UBS", "Valor_Variavel_Fluxo", "Tipo_UBS"]].copy()
        df2 = df2.sort_values("Valor_Variavel_Fluxo")
        df_plot = pd.concat([df2.head(topn // 2), df2.tail(topn // 2)])
        fig = px.bar(
            df_plot,
            x="Valor_Variavel_Fluxo",
            y=df_plot["UBS"].astype(str),
            color="Valor_Variavel_Fluxo",
            color_continuous_scale=["#d62728", "#eeeeee", "#2ca02c"],
            template="plotly_white",
            title=f"Top/Bottom {topn} Valor_Variavel_Fluxo",
        )
        fig.update_layout(yaxis_title="UBS", xaxis_title="Valor_Variavel_Fluxo")
        fig.add_vline(x=0, line_color="black")
        fig.show()

    def plota_mapa_comparativo_cobertura(self):
        b = 0

    def plota_mapa_comparativo_custos_otimizacao(self):
        b = 0


if __name__ == "__main__":
    path_baseline = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\resultados_alocacao_baseline.xlsx"
    path_resultados_otimizacao_1 = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_6.xlsx"
    path_resultados_otimizacao_2 = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_7.xlsx"
    dicts_paths = {
        "Resultados_COBERTURA_MAXIMA_6": path_resultados_otimizacao_1,
        "Resultados_COBERTURA_MAXIMA_7": path_resultados_otimizacao_2,
    }

    pos_otm = posOTMFinal(path_baseline, dicts_paths)
    mapa_fluxo_equipes = pos_otm.plota_mapa_fluxo_equipes(
        cen="Resultados_COBERTURA_MAXIMA_6"
    )
    map_cen_6 = pos_otm.plota_mapa_cobertura_OTM(cen="Resultados_COBERTURA_MAXIMA_6")
    map_cen_6.save("map_cen_10.html")
