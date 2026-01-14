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


# map = self.plota_mapa_base_setores(cen=cen, incluir_ubs=True)
if __name__ == "__main__":
    path_baseline = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\resultados_alocacao_baseline.xlsx"
    path_resultados_otimizacao_1 = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_19_END.xlsx"
    path_resultados_otimizacao_2 = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Resultados_COBERTURA_MAXIMA_19_END.xlsx"
    dicts_paths = {
        "Resultados_COBERTURA_MAXIMA_19": path_resultados_otimizacao_1,
        "Resultados_COBERTURA_MAXIMA_20": path_resultados_otimizacao_2,
    }

    pos_otm = posOTMFinal(path_baseline, dicts_paths)
    mapa_fluxo_equipes = pos_otm.plota_mapa_fluxo_equipes_v2(
        cen="Resultados_COBERTURA_MAXIMA_19"
    )
    mapa_fluxo_equipes.save("map_fluxo_eq.html")
    map_cen_6 = pos_otm.plota_mapa_cobertura_OTM(cen="Resultados_COBERTURA_MAXIMA_9")
    map_cen_6.save("map_cen_10.html")
