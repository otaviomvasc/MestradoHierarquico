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
import pandas as pd
import numpy as np
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import re

"""
classe que recebe dois arquivos excel
1 -  baseline 

2 - resultados otimizacao

"""


# TODO: Ja pensar em multiplos resultados com baseline!
class AnaliseCenarioOLD:
    def __init__(self, path_baseline, dicts_resultados_otimizacao):
        self.baseline = pd.read_excel(path_baseline)
        self.dfs_otm_cobertura = dict()
        self.dfs_otm_fluxo_equipes = dict()
        self.dfs_otm_custos = dict()
        self.df_abertura_equipes = dict()
        self.dados_unidades = pd.read_excel(
            r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_PRONTOS_para_modelo_OTM\instalacoes_primarias.xlsx"
        )
        for cen, path in dicts_resultados_otimizacao.items():
            self.dfs_otm_cobertura[cen] = pd.read_excel(path, sheet_name="Sheet1")
            self.dfs_otm_fluxo_equipes[cen] = pd.read_excel(
                path, sheet_name="Fluxo_Equipes"
            )

            # self.dfs_otm_custos[cen] = pd.read_excel(path, sheet_name="Custos")
            self.df_abertura_equipes[cen] = pd.read_excel(
                path, sheet_name="Equipes_Criadas"
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

    def resumo_cnes_fluxos(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Gera um resumo por CNES com:
        - quantidade_equipes_origem: contagem de linhas de Origem_Equipe por CNES de origem
        - quantidade_equipes_destino: soma de Valor_Variavel por CNES de destino

        Retorna um DataFrame com colunas: ['cnes', 'quantidade_equipes_origem', 'quantidade_equipes_destino'].
        """

        def fix_cnes_candidatos(ubs_destino, indice_ubs, valor_v):
            if ubs_destino == 0 and valor_v > 0:
                return indice_ubs  # Setor censitario candidato que foi aberto!
            return ubs_destino

        df["cnes_UBS_destino"] = df.apply(
            lambda x: fix_cnes_candidatos(
                x.cnes_UBS_destino, x.Indice_UBS, x.Valor_Variavel
            ),
            axis=1,
        )
        cols_lower = {c: c.lower() for c in df.columns}
        # Detecta colunas CNES de origem e destino de forma robusta a variações de nome
        origem_cnes_col = next(
            (
                c
                for c in df.columns
                if ("cnes" in cols_lower[c] and "orig" in cols_lower[c])
            ),
            None,
        )
        destino_cnes_col = next(
            (
                c
                for c in df.columns
                if ("cnes" in cols_lower[c] and "dest" in cols_lower[c])
            ),
            None,
        )
        if origem_cnes_col is None:
            raise KeyError(
                "Coluna de CNES de origem não encontrada (ex.: 'cnes_ubs_origem')."
            )
        if destino_cnes_col is None:
            raise KeyError(
                "Coluna de CNES de destino não encontrada (ex.: 'cnes_UBS_destino')."
            )

        if "Origem_Equipe" not in df.columns:
            raise KeyError("Coluna 'Origem_Equipe' não encontrada no DataFrame.")
        if "Valor_Variavel" not in df.columns:
            raise KeyError("Coluna 'Valor_Variavel' não encontrada no DataFrame.")

        origem_counts = (
            df.groupby(origem_cnes_col)["Origem_Equipe"].count().reset_index()
        )
        origem_counts = origem_counts.rename(
            columns={
                origem_cnes_col: "cnes",
                "Origem_Equipe": "quantidade_equipes_origem",
            }
        )

        destino_sums = (
            df.groupby(destino_cnes_col)["Valor_Variavel"].sum().reset_index()
        )
        destino_sums = destino_sums.rename(
            columns={
                destino_cnes_col: "cnes",
                "Valor_Variavel": "quantidade_equipes_destino",
            }
        )

        resumo = origem_counts.merge(destino_sums, on="cnes", how="outer").fillna(0)
        # Tipos
        resumo["quantidade_equipes_origem"] = resumo[
            "quantidade_equipes_origem"
        ].astype(int)
        # Mantém destino como float para suportar somas fracionárias caso existam
        return resumo.sort_values("cnes").reset_index(drop=True)

    def plota_mapa_base_setores(
        self,
        cen,
        incluir_ubs=True,
        cor_setor="#1f77b4",
        mostrar_ivs=False,
        ivs_palette="Reds",
        marca_setores=False,
    ):
        """
        Constrói um mapa base com os pontos dos setores censitários (e opcionalmente UBS).

        - cen: nome do cenário para ler colunas Lat_Demanda_{cen}, Lon_Demanda_{cen}
               e (opcionalmente) Lat_UBS_{cen}, Lon_UBS_{cen}.
        - incluir_ubs: se True, adiciona marcadores das UBS (pretos) por cima.
        - cor_setor: cor dos pontos dos setores.
        - mostrar_ivs: se True, adiciona um fundo coroplético pelo IVS.
        - ivs_palette: paleta para o IVS (ex.: "Reds").

        Retorna: folium.Map
        """
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

        mapa_base = folium.Map(
            location=[self.lat_long_contagem[0], self.lat_long_contagem[1]],
            tiles="cartodbpositron",
            control_scale=True,
            prefer_canvas=True,
            zoom_start=11,
        )

        # Panes para controlar ordem de sobreposição
        folium.map.CustomPane(name="ubs_top", z_index=650).add_to(mapa_base)
        folium.map.CustomPane(name="demanda_mid", z_index=635).add_to(mapa_base)

        # Camadas
        ubs_layer = folium.FeatureGroup(name="Unidades de saúde")
        demanda_layer = folium.FeatureGroup(name="Setores (pontos)")

        # Fundo coroplético do IVS (opcional)
        if mostrar_ivs:
            col_ivs = (
                f"IVS_{cen}"
                if f"IVS_{cen}" in resultado.columns
                else ("IVS" if "IVS" in resultado.columns else None)
            )
            if col_ivs is not None:
                resultado_choropleth = resultado[["geometry", col_ivs]].copy()
                if not isinstance(resultado_choropleth, gpd.GeoDataFrame):
                    resultado_choropleth = gpd.GeoDataFrame(
                        resultado_choropleth,
                        geometry=(
                            gpd.GeoSeries.from_wkt(resultado_choropleth["geometry"])
                            if resultado_choropleth["geometry"].dtype == "O"
                            else resultado_choropleth["geometry"]
                        ),
                    )
                resultado_choropleth = resultado_choropleth.reset_index(drop=True)
                resultado_choropleth["id"] = resultado_choropleth.index
                if not resultado_choropleth.crs:
                    resultado_choropleth.set_crs(epsg=4326, inplace=True)
                elif resultado_choropleth.crs.to_epsg() != 4326:
                    resultado_choropleth = resultado_choropleth.to_crs(epsg=4326)

                min_val = float(resultado_choropleth[col_ivs].min())
                max_val = float(resultado_choropleth[col_ivs].max())
                quantis = [
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
                bins = (
                    [min_val]
                    + list(resultado_choropleth[col_ivs].quantile(quantis))
                    + [max_val]
                )
                bins = sorted(list(set(bins)))

                folium.Choropleth(
                    geo_data=resultado_choropleth,
                    name="IVS (fundo)",
                    data=resultado_choropleth,
                    columns=["id", col_ivs],
                    key_on="feature.id",
                    fill_color=ivs_palette,
                    fill_opacity=0.6,
                    line_opacity=0.3,
                    line_color="black",
                    line_weight=0.5,
                    smooth_factor=0.8,
                    nan_fill_color="LightGray",
                    legend_name="Índice de Vulnerabilidade (IVS)",
                    bins=bins,
                ).add_to(mapa_base)
        for _, row in resultado.iterrows():
            # Coordenadas demanda
            lat_dem = row.get(f"Lat_Demanda_{cen}")
            lon_dem = row.get(f"Lon_Demanda_{cen}")
            if pd.isna(lon_dem):
                lon_dem = row.get(f"Long_Demanda_{cen}")
            if marca_setores:
                if pd.notna(lat_dem) and pd.notna(lon_dem):
                    folium.CircleMarker(
                        location=[lat_dem, lon_dem],
                        radius=2,
                        color=cor_setor,
                        fill=True,
                        fill_color=cor_setor,
                        fill_opacity=0.9,
                        opacity=0.9,
                        weight=0,
                        pane="demanda_mid",
                    ).add_to(demanda_layer)

            if incluir_ubs:
                lat_ubs = row.get(f"Lat_UBS_{cen}")
                lon_ubs = row.get(f"Lon_UBS_{cen}")
                if pd.isna(lon_ubs):
                    lon_ubs = row.get(f"Long_UBS_{cen}")
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
                        tooltip=row.get(f"UBS_Alocada_{cen}"),
                    ).add_to(ubs_layer)

        # Adiciona as camadas
        demanda_layer.add_to(mapa_base)
        if incluir_ubs:
            ubs_layer.add_to(mapa_base)

        folium.LayerControl().add_to(mapa_base)
        return mapa_base

    def plota_mapa_cobertura_OTM(self, cen):
        # Reaproveita o mapa base com setores e UBS
        map = self.plota_mapa_base_setores(cen=cen, incluir_ubs=True)

        # Precisamos novamente do GeoDataFrame filtrado para coroplético/linhas
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

        # Pane e camada para ligações (demanda → UBS)
        folium.map.CustomPane(name="links_mid", z_index=640).add_to(map)
        ligacao_layer = folium.FeatureGroup(name="Ligação Demanda → UBS")

        for index, cnes in resultado.iterrows():
            try:
                lat_ubs = cnes.get(f"Lat_UBS_{cen}")
                lon_ubs = cnes.get(f"Lon_UBS_{cen}")
                if pd.isna(lon_ubs):
                    lon_ubs = cnes.get(f"Long_UBS_{cen}")

                lat_dem = cnes.get(f"Lat_Demanda_{cen}")
                lon_dem = cnes.get(f"Lon_Demanda_{cen}")
                if pd.isna(lon_dem):
                    lon_dem = cnes.get(f"Long_Demanda_{cen}")

                if (
                    pd.notna(lat_dem)
                    and pd.notna(lon_dem)
                    and pd.notna(lat_ubs)
                    and pd.notna(lon_ubs)
                ):
                    folium.PolyLine(
                        locations=[[lat_dem, lon_dem], [lat_ubs, lon_ubs]],
                        color="#2c7fb8",
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

        # Adiciona a camada de ligações por cima dos pontos
        ligacao_layer.add_to(map)

        # Add the marker cluster to the map

        folium.LayerControl().add_to(map)
        return map

    def plota_mapa_cobertura_otimizacao(self):
        b = 0

    def plota_mapa_fluxo_equipes(self, cen):
        df = self.dfs_otm_fluxo_equipes[cen].copy()
        df_eq = df[df.tipo_equipe == 1].copy()
        # Mantém apenas linhas com coordenadas válidas (Valor_Variavel pode ser nulo)
        df = df[
            df[
                [
                    "lat_origem",
                    "long_origem",
                    "lat_destino",
                    "long_destino",
                ]
            ]
            .notna()
            .all(axis=1)
        ].copy()

        # Mapa base centralizado em Contagem
        map_fluxos = folium.Map(
            location=[self.lat_long_contagem[0], self.lat_long_contagem[1]],
            tiles="cartodbpositron",
            control_scale=True,
            prefer_canvas=True,
            zoom_start=11,
        )

        # Panes para controlar ordem de sobreposição
        folium.map.CustomPane(name="origens_mid", z_index=635).add_to(map_fluxos)
        folium.map.CustomPane(name="destinos_mid", z_index=636).add_to(map_fluxos)
        folium.map.CustomPane(name="links_mid", z_index=637).add_to(map_fluxos)

        # Trabalhar somente com tipo_equipe == 1 e agregar por origem
        if "tipo_equipe" in df.columns:
            df_eq = df[df.tipo_equipe == 1].copy()
        else:
            df_eq = df.copy()

        if df_eq.empty:
            folium.LayerControl(collapsed=False).add_to(map_fluxos)
            return map_fluxos

        agg_base = (
            df_eq.groupby("Indice_UBS")
            .agg(total_fluxo=("Valor_Variavel", "sum"))
            .reset_index()
        )
        coords = (
            df_eq.groupby("Indice_UBS")
            .agg(lat=("lat_origem", "first"), lon=("long_origem", "first"))
            .reset_index()
        )
        agg_df = agg_base.merge(coords, on="Indice_UBS", how="left")
        agg_df["total_fluxo"] = agg_df["total_fluxo"].fillna(0.0)

        eqs_inicio = (
            df_eq.groupby(by=["Indice_equipe"])
            .agg({"Origem_Equipe": "first"})
            .reset_index()
        )
        # Tudo isso aqui so para saber quantas equipes existiam em cada CNES antes da otimizacao!
        df_un = self.dados_unidades[
            self.dados_unidades.municipio_nome == "CONTAGEM"
        ].reset_index(drop=True)
        eqs_inicio["cnes"] = eqs_inicio.Origem_Equipe.apply(
            lambda x: (
                df_un.cnes.iloc[x - 1]
                if x - 1 <= len(df_un.cnes)
                else "Local_Candidato"
            )
        )
        agg_df["cnes"] = agg_df.Indice_UBS.apply(
            lambda x: (
                df_un.cnes.iloc[x - 1]
                if x - 1 <= len(df_un.cnes)
                else "Local_Candidato"
            )
        )

        # eqs_inicio["latitude"] = eqs_inicio.Origem_Equipe.apply(lambda x: df_un.latitude.iloc[x-1] if x-1 <= len(df_un.cnes) else "Local_Candidato")
        # eqs_inicio["longitude"] = eqs_inicio.Origem_Equipe.apply(lambda x: df_un.longitude.iloc[x-1] if x-1 <= len(df_un.cnes) else "Local_Candidato")
        df_qntd_equipes_inicio = (
            eqs_inicio.groupby(by="cnes").agg({"Indice_equipe": "count"}).reset_index()
        )
        df_qntd_equipes_inicio = df_qntd_equipes_inicio.merge(
            df_un, on="cnes", how="left"
        )
        df_qntd_equipes_inicio = df_qntd_equipes_inicio.rename(
            columns={"Indice_equipe": "Quantidade_Inicial_Equipes"}
        )
        df_agg_end = agg_df.merge(df_qntd_equipes_inicio, on="cnes", how="left")
        df_agg_end["Quantidade_Inicial_Equipes"] = (
            df_agg_end.Quantidade_Inicial_Equipes.fillna(0)
        )
        # Das Equipes iniciais, quantas a unidade perdeu ?
        camada_origens = folium.FeatureGroup(name="Resumo por origem (tipo 1)")
        for _, r in df_agg_end.iterrows():
            lat = r["lat"]
            lon = r["lon"]
            if pd.isna(lat) or pd.isna(lon):
                continue
            try:
                lat = float(lat)
                lon = float(lon)
            except Exception:
                continue
            if not (np.isfinite(lat) and np.isfinite(lon)):
                continue

            tooltip = (
                f"CNES : {r['cnes']}\n"
                f"Nome : {r['nome_fantasia']}\n"
                f"Quantidade Inicial Equipes : {r['Quantidade_Inicial_Equipes']}\n"
                f"Quantidade Final: {r['total_fluxo']:.2f}\n"
            )
            folium.CircleMarker(
                location=[lat, lon],
                radius=4,
                color="#2c7fb8",
                fill=True,
                fill_color="#2c7fb8",
                fill_opacity=0.9,
                opacity=0.9,
                weight=0,
                pane="origens_mid",
                tooltip=tooltip,
            ).add_to(camada_origens)

        camada_origens.add_to(map_fluxos)

        folium.LayerControl(collapsed=False).add_to(map_fluxos)
        return map_fluxos  # map_fluxos.save("map_fluxo_eq_2.html")

    def plota_mapa_fluxo_equipes_v2(self, cen):
        df = self.dfs_otm_fluxo_equipes[cen].copy()
        # TODO: Entender porque nem todas as 205 equipes estao aqui!
        # Mantém apenas linhas com coordenadas válidas (Valor_Variavel pode ser nulo)
        df = df[
            df[
                [
                    "lat_origem",
                    "long_origem",
                    "lat_destino",
                    "long_destino",
                ]
            ]
            .notna()
            .all(axis=1)
        ].copy()

        # Mapa base centralizado em Contagem
        map = self.plota_mapa_base_setores(cen=cen, incluir_ubs=True, mostrar_ivs=True)

        # Trabalhar somente com tipo_equipe == 1 e agregar por origem
        if "tipo_equipe" in df.columns:
            df_eq = df[df.tipo_equipe == 1].copy()
        else:
            df_eq = df.copy()

        if df_eq.empty:
            folium.LayerControl(collapsed=False).add_to(map)
            # return map

        # eqs_inicio["latitude"] = eqs_inicio.Origem_Equipe.apply(lambda x: df_un.latitude.iloc[x-1] if x-1 <= len(df_un.cnes) else "Local_Candidato")
        # eqs_inicio["longitude"] = eqs_inicio.Origem_Equipe.apply(lambda x: df_un.longitude.iloc[x-1] if x-1 <= len(df_un.cnes) else "Local_Candidato")

        resumo = self.resumo_cnes_fluxos(df_eq)
        # pegar equipes criadas!
        # df_merge = df_eq.merge(df_eq_criadas, right_on = "Unidade_UBS", left_on = "Indice_UBS", how="outer")

        # Refazer essa parte!
        # df_eq_criadas = self.df_abertura_equipes[cen]
        # df_cr = df_eq_criadas[df_eq_criadas.eq_ESF_criadas > 0]
        # df_merge = df_eq.merge(df_eq_criadas, right_on = "Unidade_UBS", left_on = "Indice_UBS", how="outer")

        # Das Equipes iniciais, quantas a unidade perdeu ?
        # Fluxos: usar o dataframe geral filtrado, não apenas tipo_equipe==1
        df_fluxo = df[df.Valor_Variavel > 0].reset_index(drop=True)
        print(f"Linhas de fluxo a desenhar: {len(df_fluxo)}")

        # Pane e camada para fluxos (acima de UBS e demais)
        folium.map.CustomPane(name="flows_top", z_index=700).add_to(map)
        camada_fluxos = folium.FeatureGroup(name="Fluxo de equipes")

        for _, r in df_fluxo.iterrows():
            lat_o = r.get("lat_origem")
            lon_o = r.get("long_origem")
            lat_d = r.get("lat_destino")
            lon_d = r.get("long_destino")
            if pd.isna(lat_o) or pd.isna(lon_o) or pd.isna(lat_d) or pd.isna(lon_d):
                continue
            try:
                lat_o = float(lat_o)
                lon_o = float(lon_o)
                lat_d = float(lat_d)
                lon_d = float(lon_d)
            except Exception:
                continue
            if not (
                np.isfinite(lat_o)
                and np.isfinite(lon_o)
                and np.isfinite(lat_d)
                and np.isfinite(lon_d)
            ):
                continue
            print(f"fluxo equipe {r.cnes_eq} plotado")
            folium.PolyLine(
                locations=[[lat_o, lon_o], [lat_d, lon_d]],
                color="#ff5722",
                weight=3.5,
                opacity=1.0,
                pane="flows_top",
                tooltip=f"Fluxo equipe {r.get('Indice_equipe', '')}",
            ).add_to(camada_fluxos)

        camada_fluxos.add_to(map)
        folium.LayerControl().add_to(map)
        map.save("map_fluxo_eq_FINAL_6.html")
        return map


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
                fill_opacity=0.9,  # Aumentando opacidade
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
                color="black",
                fillColor="black",
                fillOpacity=0.9,
                weight=2,
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

        # fig.write_html("dist_distancia_cenario.html")
        return fig


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
            "Custo Fixo Mensal": 130000,
        }
        # TODO: Vai ser fundamental a analise de acessibilidade geografica e capacidade maxima de atendimento nas UBS!
        self.calcula_custos_reais()

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
        return fig
        # fig.write_image("comparacao_cobertura.png", width=1400, height=1200)


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
        fig_cenario = self.cenario.plota_acessibilidade_geografica_cenario()
        fig_baseline = self.baseline.plota_acessibilidade_geografica()
        # fig_cenario = self.plota_acessibilidade_geografica_cenario

    def analises(self, tamanho_faixa=50):
        self.plota_comparativo_acessibilidade()
        # Analises descritivas de quantidades de equipes reais x criadas
        self.analises_descritivas()
        # Analise de custo - Diferenca entre baseline e modelo

        figura, dados = self.analisa_cobertura_comparativa_por_ivs_2(
            tamanho_faixa=tamanho_faixa
        )
        figura.show()
        figura.write_html("comparacao_cobertura_custos_reais.html")
        figura.write_image("comparacao_cobertura.png", width=1400, height=1200)

        # Proximas analises = Dados de custo e quantitativo de equipes real x criadas!

    def analises_descritivas(self):
        # populacao total atendida por Esf, EsB,
        # Populacao_Atendida_ESF, Populacao_Atendida_ESB
        # populacao_ajustada_eSF, populacao_ajustada_eSB,
        populacao_total = self.df_merge.Populacao_Total.sum()
        modelo_ESF = self.df_merge.Populacao_Atendida_ESF.sum()
        modelo_ESB = self.df_merge.Populacao_Atendida_ESB.sum()
        real_ESF = self.df_merge.pop_captada_eSF.sum()
        real_ESB = self.df_merge.pop_captada_eSB.sum()

        total_modelo = modelo_ESF + modelo_ESB
        total_real = real_ESF + real_ESB

        # Calcular a variação percentual entre total_modelo e total_real
        if total_real != 0:
            variacao_percentual = ((total_modelo - total_real) / total_real) * 100
        else:
            variacao_percentual = float("nan")

        print(f"População total: {populacao_total}")
        print(f"Modelo - População Atendida ESF: {modelo_ESF}")
        print(f"Modelo - População Atendida ESB: {modelo_ESB}")
        print(f"Real - População Captada ESF: {real_ESF}")
        print(f"Real - População Captada ESB: {real_ESB}")
        print(f"Total Modelo (ESF + ESB): {total_modelo}")
        print(f"Total Real (ESF + ESB): {total_real}")

        # Analise de custos!
        custos_equipe_real = self.baseline.custo_equipes_real
        custos_equipe_modelo = self.cenario.df_custos

        import pandas as pd
        import matplotlib.pyplot as plt
        import seaborn as sns

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
        # GRÁFICOS PRONTOS PARA USO
        # ============================================================================================================
        fig = make_subplots(
            rows=3,
            cols=2,
            subplot_titles=(
                "Custos por Tipo de Equipe (Empilhado)",
                "Custos Totais por Categoria",
                "Custos por Tipo de Despesa",
                "Custos Operacionais Reais (Mensal)",
                "Distribuição Percentual dos Custos",
                "Resumo: Custo Total do Sistema",
            ),
            specs=[
                [{"type": "bar"}, {"type": "bar"}],
                [{"type": "bar"}, {"type": "bar"}],
                [{"type": "pie"}, {"type": "bar"}],
            ],
            vertical_spacing=0.12,
            horizontal_spacing=0.10,
        )

        # Cores padronizadas
        cores = {"ESF": "#1f77b4", "ESB": "#ff7f0e", "ENASF": "#2ca02c"}

        # ============================================================================================================
        # SUBPLOT 1: Custos por tipo de equipe (empilhado)
        # ============================================================================================================

        for equipe in ["ESF", "ESB", "ENASF"]:
            df_temp = df_por_equipe[df_por_equipe["Nivel"] == equipe]
            fig.add_trace(
                go.Bar(
                    x=df_temp["Tipo_Custo"],
                    y=df_temp["Valor_Milhoes"],
                    name=equipe,
                    marker_color=cores[equipe],
                    text=df_temp["Percentual"].apply(lambda x: f"{x:.1f}%"),
                    textposition="inside",
                    legendgroup="equipe",
                    showlegend=True,
                ),
                row=1,
                col=1,
            )

        # ============================================================================================================
        # SUBPLOT 2: Custos totais por categoria
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_totais["Tipo_Custo"],
                y=df_totais["Valor_Milhoes"],
                marker_color="steelblue",
                text=df_totais.apply(
                    lambda row: f"R$ {row['Valor_Milhoes']:.2f}M<br>({row['Percentual']:.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=1,
            col=2,
        )

        # ============================================================================================================
        # SUBPLOT 3: Custos por tipo de despesa
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_por_tipo["Tipo_Custo"],
                y=df_por_tipo["Valor_Milhoes"],
                marker_color=["#66c2a5", "#fc8d62", "#8da0cb"],
                text=df_por_tipo.apply(
                    lambda row: f"R$ {row['Valor_Milhoes']:.2f}M<br>({row['Percentual']:.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=1,
        )

        # ============================================================================================================
        # SUBPLOT 4: Custos reais operacionais
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_custos_reais_formatado["DS_EQUIPE"],
                y=df_custos_reais_formatado["Custo_Mensal_Milhoes"],
                marker_color=[
                    cores.get(x.split("-")[0].strip(), "gray")
                    for x in df_custos_reais_formatado["DS_EQUIPE"]
                ],
                text=df_custos_reais_formatado.apply(
                    lambda row: f"{int(row['Qntd_Equipes'])} eq.<br>R$ {row['Custo_Mensal_Milhoes']:.2f}M<br>({row['Percentual']:.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=2,
        )

        # ============================================================================================================
        # SUBPLOT 5: Pizza - Distribuição percentual
        # ============================================================================================================

        fig.add_trace(
            go.Pie(
                labels=df_totais["Tipo_Custo"],
                values=df_totais["Valor_Milhoes"],
                hole=0.4,
                marker=dict(colors=["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728"]),
                textinfo="label+percent",
                textposition="outside",
                showlegend=False,
            ),
            row=3,
            col=1,
        )

        # ============================================================================================================
        # SUBPLOT 6: Resumo - Custo total
        # ============================================================================================================

        df_resumo = custos_equipe_modelo[
            custos_equipe_modelo["Tipo_Custo"] == "CUSTO TOTAL"
        ].copy()
        custo_total = df_resumo["Valor_R"].values[0] / 1e6

        # Breakdown dos principais componentes
        componentes = [
            "Total Contratação",
            "Total Realocação",
            "Total Operação",
            "Total Infraestrutura",
        ]
        df_breakdown = custos_equipe_modelo[
            custos_equipe_modelo["Tipo_Custo"].isin(componentes)
        ].copy()
        df_breakdown["Valor_Milhoes"] = df_breakdown["Valor_R"] / 1e6

        fig.add_trace(
            go.Bar(
                x=df_breakdown["Tipo_Custo"].str.replace("Total ", ""),
                y=df_breakdown["Valor_Milhoes"],
                marker_color=["#e74c3c", "#f39c12", "#3498db", "#95a5a6"],
                text=df_breakdown["Percentual"].apply(lambda x: f"{x:.1f}%"),
                textposition="outside",
                showlegend=False,
            ),
            row=3,
            col=2,
        )

        # ============================================================================================================
        # FORMATAÇÃO GLOBAL
        # ============================================================================================================

        fig.update_xaxes(tickangle=-45, showgrid=False)
        fig.update_yaxes(
            title_text="Valor (Milhões R$)", showgrid=True, gridcolor="lightgray"
        )

        fig.update_layout(
            height=1400,
            width=1600,
            title_text=f"<b>Análise de Custos do Sistema de Saúde - Custo Total: R$ {custo_total:.2f} Milhões</b>",
            title_x=0.5,
            title_font_size=20,
            showlegend=True,
            legend=dict(
                orientation="h",
                yanchor="top",
                y=1.02,
                xanchor="center",
                x=0.25,
                title="Tipo de Equipe",
            ),
            plot_bgcolor="white",
            paper_bgcolor="white",
            font=dict(family="Arial, sans-serif", size=10, color="black"),
            barmode="stack",  # Para o gráfico empilhado
        )

        # Atualizar grid para todos os eixos
        fig.update_xaxes(showline=True, linewidth=1, linecolor="lightgray", mirror=True)
        fig.update_yaxes(showline=True, linewidth=1, linecolor="lightgray", mirror=True)

        fig.show()
        fig.write_html("analise_custos_completa.html")
        # Salvar (opcional)
        # fig.write_html("analise_custos_completa.html")
        fig.write_image("analise_custos_completa.png", width=1600, height=1400, scale=2)
        # populacao ponderada por IVS coberta por Esf, Esb,
        # Total coberto
        # Porcentagem
        #

        ### COMPARACAO COM REAL####
        # Preparar dados para comparação Modelo vs Real
        df_modelo_operacional = custos_equipe_modelo[
            custos_equipe_modelo["Tipo_Custo"].isin(
                ["Operação ESF", "Operação ESB", "Operação ENASF"]
            )
        ].copy()
        df_modelo_operacional["Valor_Milhoes"] = df_modelo_operacional["Valor_R"] / 1e6
        df_modelo_operacional["Tipo_Equipe"] = df_modelo_operacional[
            "Tipo_Custo"
        ].str.replace("Operação ", "")

        # Preparar custos reais
        df_real_comp = df_custos_reais_formatado.copy()
        df_real_comp["Tipo_Equipe"] = (
            df_real_comp["DS_EQUIPE"].str.split("-").str[0].str.strip()
        )

        # Criar dataframe de comparação
        comparacao_data = []
        for equipe in ["ESF", "ESB", "ENASF"]:
            custo_modelo = df_modelo_operacional[
                df_modelo_operacional["Tipo_Equipe"] == equipe
            ]["Valor_Milhoes"].values
            custo_modelo = custo_modelo[0] if len(custo_modelo) > 0 else 0

            custo_real = df_real_comp[df_real_comp["Tipo_Equipe"] == equipe][
                "Custo_Mensal_Milhoes"
            ].values
            custo_real = custo_real[0] if len(custo_real) > 0 else 0

            comparacao_data.append(
                {
                    "Tipo_Equipe": equipe,
                    "Custo_Modelo": custo_modelo,
                    "Custo_Real": custo_real,
                    "Diferenca": custo_modelo - custo_real,
                    "Diferenca_Percentual": (
                        ((custo_modelo - custo_real) / custo_real * 100)
                        if custo_real > 0
                        else 0
                    ),
                }
            )

        df_comparacao = pd.DataFrame(comparacao_data)

        # ============================================================================================================
        # CRIAR FIGURE COM SUBPLOTS
        # ============================================================================================================

        fig = make_subplots(
            rows=3,
            cols=2,
            subplot_titles=(
                "Custos Operacionais: Modelo vs Real (Mensal)",
                "Diferença entre Modelo e Real",
                "Custos Totais por Categoria (Modelo)",
                "Custos por Tipo de Despesa (Modelo)",
                "Distribuição Percentual dos Custos",
                "Resumo: Breakdown do Custo Total",
            ),
            specs=[
                [{"type": "bar"}, {"type": "bar"}],
                [{"type": "bar"}, {"type": "bar"}],
                [{"type": "pie"}, {"type": "bar"}],
            ],
            vertical_spacing=0.12,
            horizontal_spacing=0.10,
        )

        cores = {"ESF": "#1f77b4", "ESB": "#ff7f0e", "ENASF": "#2ca02c"}

        # ============================================================================================================
        # SUBPLOT 1: Comparação Modelo vs Real (barras agrupadas)
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_comparacao["Tipo_Equipe"],
                y=df_comparacao["Custo_Modelo"],
                name="Custo Modelo",
                marker_color="#3498db",
                text=df_comparacao["Custo_Modelo"].apply(lambda x: f"R$ {x:.2f}M"),
                textposition="outside",
                legendgroup="comparacao",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        fig.add_trace(
            go.Bar(
                x=df_comparacao["Tipo_Equipe"],
                y=df_comparacao["Custo_Real"],
                name="Custo Real",
                marker_color="#e74c3c",
                text=df_comparacao["Custo_Real"].apply(lambda x: f"R$ {x:.2f}M"),
                textposition="outside",
                legendgroup="comparacao",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        # ============================================================================================================
        # SUBPLOT 2: Diferença entre Modelo e Real
        # ============================================================================================================

        cores_diff = [
            "#27ae60" if x >= 0 else "#e74c3c" for x in df_comparacao["Diferenca"]
        ]

        fig.add_trace(
            go.Bar(
                x=df_comparacao["Tipo_Equipe"],
                y=df_comparacao["Diferenca"],
                marker_color=cores_diff,
                text=df_comparacao.apply(
                    lambda row: f"R$ {row['Diferenca']:.2f}M<br>({row['Diferenca_Percentual']:+.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=1,
            col=2,
        )

        # Adicionar linha zero
        fig.add_hline(y=0, line_dash="dash", line_color="gray", row=1, col=2)

        # ============================================================================================================
        # SUBPLOT 3: Custos totais por categoria
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_totais["Tipo_Custo"],
                y=df_totais["Valor_Milhoes"],
                marker_color="steelblue",
                text=df_totais.apply(
                    lambda row: f"R$ {row['Valor_Milhoes']:.2f}M<br>({row['Percentual']:.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=1,
        )

        # ============================================================================================================
        # SUBPLOT 4: Custos por tipo de despesa
        # ============================================================================================================

        fig.add_trace(
            go.Bar(
                x=df_por_tipo["Tipo_Custo"],
                y=df_por_tipo["Valor_Milhoes"],
                marker_color=["#66c2a5", "#fc8d62", "#8da0cb"],
                text=df_por_tipo.apply(
                    lambda row: f"R$ {row['Valor_Milhoes']:.2f}M<br>({row['Percentual']:.1f}%)",
                    axis=1,
                ),
                textposition="outside",
                showlegend=False,
            ),
            row=2,
            col=2,
        )

        # ============================================================================================================
        # SUBPLOT 5: Pizza - Distribuição percentual
        # ============================================================================================================

        fig.add_trace(
            go.Pie(
                labels=df_totais["Tipo_Custo"],
                values=df_totais["Valor_Milhoes"],
                hole=0.4,
                marker=dict(colors=["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728"]),
                textinfo="label+percent",
                textposition="outside",
                showlegend=False,
            ),
            row=3,
            col=1,
        )

        # ============================================================================================================
        # SUBPLOT 6: Breakdown do custo total
        # ============================================================================================================
        custos_equipe_real = self.baseline.custo_equipes_real
        custos_equipe_modelo = self.cenario.df_custos

        componentes = [
            "Total Contratação",
            "Total Realocação",
            "Total Operação",
            "Total Infraestrutura",
        ]
        df_breakdown = custos_equipe_modelo[
            custos_equipe_modelo["Tipo_Custo"].isin(componentes)
        ].copy()
        df_breakdown["Valor_Milhoes"] = df_breakdown["Valor_R"] / 1e6

        fig.add_trace(
            go.Bar(
                x=df_breakdown["Tipo_Custo"].str.replace("Total ", ""),
                y=df_breakdown["Valor_Milhoes"],
                marker_color=["#e74c3c", "#f39c12", "#3498db", "#95a5a6"],
                text=df_breakdown["Percentual"].apply(lambda x: f"{x:.1f}%"),
                textposition="outside",
                showlegend=False,
            ),
            row=3,
            col=2,
        )

        # ============================================================================================================
        # FORMATAÇÃO GLOBAL
        # ============================================================================================================

        df_resumo = custos_equipe_modelo[
            custos_equipe_modelo["Tipo_Custo"] == "CUSTO TOTAL"
        ].copy()
        custo_total = df_resumo["Valor_R"].values[0] / 1e6

        fig.update_xaxes(tickangle=-45, showgrid=False)
        fig.update_yaxes(
            title_text="Valor (Milhões R$)", showgrid=True, gridcolor="lightgray"
        )

        # Ajustar título do eixo Y no subplot 2 (diferença)
        fig.update_yaxes(title_text="Diferença (Milhões R$)", row=1, col=2)

        fig.update_layout(
            height=1400,
            width=1600,
            title_text=f"<b>Análise Comparativa de Custos - Modelo vs Real | Custo Total Modelo: R$ {custo_total:.2f} Milhões</b>",
            title_x=0.5,
            title_font_size=18,
            showlegend=True,
            legend=dict(
                orientation="h", yanchor="top", y=1.02, xanchor="center", x=0.25
            ),
            plot_bgcolor="white",
            paper_bgcolor="white",
            font=dict(family="Arial, sans-serif", size=10, color="black"),
            barmode="group",
        )

        fig.update_xaxes(showline=True, linewidth=1, linecolor="lightgray", mirror=True)
        fig.update_yaxes(showline=True, linewidth=1, linecolor="lightgray", mirror=True)

        fig.show()

        # Imprimir resumo da comparação
        print("\n=== RESUMO DA COMPARAÇÃO MODELO vs REAL ===")
        print(df_comparacao.to_string(index=False))
        print(f"\nDiferença Total: R$ {df_comparacao['Diferenca'].sum():.2f} Milhões")

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
        df_resultados_esf = pd.DataFrame(resultados_dict["ESF"])
        df_resultados_esb = pd.DataFrame(resultados_dict["ESB"])

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
                x=df_resultados_esf["Faixa"],
                y=df_resultados_esf["Pop_Captada"],
                name="Baseline",
                marker_color=cor_captada,
                text=df_resultados_esf["Pop_Captada"].apply(lambda x: f"{x:,.0f}"),
                textposition="outside",
                legendgroup="captada",
                showlegend=True,
            ),
            row=1,
            col=1,
        )

        fig.add_trace(
            go.Bar(
                x=df_resultados_esf["Faixa"],
                y=df_resultados_esf["Pop_Atendida"],
                name="Modelo",
                marker_color=cor_atendida,
                text=df_resultados_esf["Pop_Atendida"].apply(lambda x: f"{x:,.0f}"),
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
                x=df_resultados_esb["Faixa"],
                y=df_resultados_esb["Pop_Captada"],
                name="Baseline",
                marker_color=cor_captada,
                text=df_resultados_esb["Pop_Captada"].apply(lambda x: f"{x:,.0f}"),
                textposition="outside",
                legendgroup="captada",
                showlegend=False,
            ),
            row=1,
            col=2,
        )

        fig.add_trace(
            go.Bar(
                x=df_resultados_esb["Faixa"],
                y=df_resultados_esb["Pop_Atendida"],
                name="Modelo",
                marker_color=cor_atendida,
                text=df_resultados_esb["Pop_Atendida"].apply(lambda x: f"{x:,.0f}"),
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
            for x in df_resultados_esf["Diferenca"]
        ]
        fig.add_trace(
            go.Bar(
                x=df_resultados_esf["Faixa"],
                y=df_resultados_esf["Diferenca"],
                name="Diferença",
                marker_color=cores_diff_esf,
                text=df_resultados_esf["Diferenca"].apply(lambda x: f"{x:+,.0f}"),
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
            for x in df_resultados_esb["Diferenca"]
        ]
        fig.add_trace(
            go.Bar(
                x=df_resultados_esb["Faixa"],
                y=df_resultados_esb["Diferenca"],
                name="Diferença",
                marker_color=cores_diff_esb,
                text=df_resultados_esb["Diferenca"].apply(lambda x: f"{x:+,.0f}"),
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

        for tipo_equipe in ["ESF", "ESB"]:
            df_res = resultados_dict[tipo_equipe]
            total_captada = sum([r["Pop_Captada"] for r in df_res])
            total_atendida = sum([r["Pop_Atendida"] for r in df_res])
            diff_total = total_atendida - total_captada

            print(f"\n{tipo_equipe}:")
            print(f"  Total Captado: {total_captada:,.0f} pessoas")
            print(f"  Total Atendido: {total_atendida:,.0f} pessoas")
            print(
                f"  Diferença: {diff_total:+,.0f} ({(total_atendida/total_captada*100) if total_captada > 0 else 0:.1f}%)"
            )

            # Top 20
            if len(df_res) > 0:
                top_capt = df_res[0]["Pop_Captada"]
                top_atend = df_res[0]["Pop_Atendida"]
                print(f"  Top {tamanho_faixa} mais vulneráveis:")
                print(
                    f"    Captado: {top_capt:,.0f} | Atendido: {top_atend:,.0f} | "
                    f"Diferença: {(top_atend-top_capt):+,.0f}"
                )

        return fig, {"ESF": df_resultados_esf, "ESB": df_resultados_esb}

    def compara_fluxo_emulti(self):
        # TODO: Implementar comparação de fluxo emulti
        pass


def main():
    path_cenario = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_34_END.xlsx"
    path_baseline = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\resultados_Baseline_DataSus_Cobertura_por_equipes_v2.xlsx"
    comparador_cenario = ComparaResultadoBaseline(
        path_cenario=path_cenario, path_baseline=path_baseline
    )
    # comparador_cenario.analises(tamanho_faixa=50)
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
