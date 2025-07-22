# %%
import pandas as pd
import numpy as np

pd.set_option("display.max_columns", 500)


# %%
def haversine(lon1, lat1, lon2, lat2):
    """
    Calcula a distância Haversine entre dois pontos (em graus decimais).
    Retorna a distância em quilômetros.
    """
    # converter para radianos
    lon1, lat1, lon2, lat2 = map(np.radians, [lon1, lat1, lon2, lat2])
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = np.sin(dlat / 2.0) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon / 2.0) ** 2
    c = 2 * np.arcsin(np.sqrt(a))
    r = 6371  # Raio da Terra em km
    return c * r


# %%
# dados de demanda
path_cs = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_PRONTOS_para_modelo_OTM\dados_cidades_full_MG.xlsx"
path_dict_agregados = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_brutos_demanda\dicionario_de_dados_agregados_por_setores_censitarios_20250417.xlsx"
path_dados_agregados = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_brutos_demanda\Agregados_por_setores_demografia_BR.csv"
path_dados_ivs = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_brutos_demanda\atlasivs_dadosbrutos_Belo_Horizonte_v2.xlsx"

# %%
df_cs = pd.read_excel(path_cs)
df_dict_agregados = pd.read_excel(path_dict_agregados, sheet_name="Dicionário não PCT")
df_dados_agregados = pd.read_csv(path_dados_agregados, sep=";")
df_cs["CD_SETOR_MERGE"] = df_cs.CD_SETOR.apply(lambda x: int(x[:-1]))
df_ivs = pd.read_excel(path_dados_ivs, "UDH")  # aba UDH
# %%

indices_demograficos = [
    "CD_setor",
    "V01009",
    "V01010",
    "V01011",
    "V01012",
    "V01013",
    "V01014",
    "V01015",
    "V01016",
    "V01017",
    "V01018",
    "V01019",
    "V01020",
    "V01021",
    "V01022",
    "V01023",
    "V01024",
    "V01025",
    "V01026",
    "V01027",
    "V01028",
    "V01029",
    "V01030",
]

indices_demograficos_dict = df_dict_agregados[
    df_dict_agregados.Variável.isin(indices_demograficos)
]["Descrição"].to_list()
indices_demograficos_dict.insert(0, "CD_setor")
df_dados_agregados_end = df_dados_agregados[indices_demograficos]
df_dados_agregados_end.columns = indices_demograficos_dict
# %%
df_cs_end = df_cs.merge(
    df_dados_agregados_end, right_on="CD_setor", left_on="CD_SETOR_MERGE", how="left"
)

# Substituir "X" por 0 nas colunas demográficas
colunas_demograficas = [
    "Sexo masculino, 0 a 4 anos",
    "Sexo masculino, 5 a 9 anos",
    "Sexo masculino, 10 a 14 anos",
    "Sexo masculino, 15 a 19 anos",
    "Sexo masculino, 20 a 24 anos",
    "Sexo masculino, 25 a 29 anos",
    "Sexo masculino, 30 a 39 anos",
    "Sexo masculino, 40 a 49 anos",
    "Sexo masculino, 50 a 59 anos",
    "Sexo masculino, 60 a 69 anos",
    "Sexo masculino, 70 anos ou mais",
    "Sexo feminino, 0 a 4 anos",
    "Sexo feminino, 5 a 9 anos",
    "Sexo feminino, 10 a 14 anos",
    "Sexo feminino, 15 a 19 anos",
    "Sexo feminino, 20 a 24 anos",
    "Sexo feminino, 25 a 29 anos",
    "Sexo feminino, 30 a 39 anos",
    "Sexo feminino, 40 a 49 anos",
    "Sexo feminino, 50 a 59 anos",
    "Sexo feminino, 60 a 69 anos",
    "Sexo feminino, 70 anos ou mais",
]

for coluna in colunas_demograficas:
    if coluna in df_cs_end.columns:
        df_cs_end[coluna] = df_cs_end[coluna].replace("X", 0)

# %%
df_cs_end.to_excel(
    r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_PRONTOS_para_modelo_OTM\dados_cidades_full_MG_com_demografia.xlsx",
    index=False,
)

# %%
# coluna nome_udh
# coluna NM_SUBDIST do df demanda!

# Se houver o nome NM_SUBST na tabela de IVS, tirar média de todos os valores de IVS
# Se nao houver, buscar CS mais proximo e pegar esse valor
df_ivs_an = df_ivs[df_ivs.ano == 2010].reset_index(drop=True)

municipios_dados_ivs = [
    i
    for i in df_cs_end.NM_MUN
    if len([k for k in df_ivs.nome_municipio_uf if i in k]) > 0
]
df_in = df_cs_end[df_cs_end.NM_MUN == "Contagem"]

# Contagem
cols_ivs = [
    "ivs",
    "ivs_infraestrutura_urbana",
    "ivs_capital_humano",
    "ivs_renda_e_trabalho",
    "idhm",
    "idhm_long",
    "idhm_educ",
    "idhm_renda",
    "idhm_educ_sub_esc",
    "idhm_educ_sub_freq",
    "prosp_soc",
    "t_sem_agua_esgoto",
    "t_sem_lixo",
    "t_vulner_mais1h",
    "t_mort1",
    "t_c0a5_fora",
    "t_c6a14_fora",
    "t_m10a17_filho",
    "t_mchefe_fundin_fmenor",
    "t_analf_15m",
    "t_cdom_fundin",
    "t_p15a24_nada",
    "t_vulner",
    "t_desocup18m",
    "t_p18m_fundin_informal",
    "t_vulner_depende_idosos",
    "t_atividade10a14",
    "espvida",
    "t_pop18m_fundc",
    "t_pop5a6_escola",
    "t_pop11a13_ffun",
    "t_pop15a17_fundc",
    "t_pop18a20_medioc",
    "renda_per_capita",
    "populacao",
    "t_fmor5",
    "t_razdep",
    "t_fectot",
    "t_env",
    "vulner15a24",
    "mchefe_fmenor",
    "vulner_dia",
    "dom_vulner_idoso",
    "pop0a1",
    "pop1a3",
    "pop4",
    "pop5",
    "pop6",
    "pop6a10",
    "pop6a17",
    "pop11a13",
    "pop11a14",
    "pop12a14",
    "pop15m",
    "pop15a17",
    "pop15a24",
    "pop16a18",
    "pop18m",
    "pop18a20",
    "pop18a24",
    "pop19a21",
    "pop25m",
    "pop65m",
    "pea10m",
    "pea10a14",
    "pea15a17",
    "pea18m",
    "t_eletrica",
    "t_densidadem2",
    "t_analf_18m",
    "t_analf_25m",
    "rdpc_def_vulner",
    "t_renda_trab",
    "i_gini",
    "t_carteira_18m",
    "t_scarteira_18m",
    "t_setorpublico_18m",
    "t_contapropria_18m",
    "t_empregador_18m",
    "t_formal_18m",
    "t_fundc_ocup18m",
    "t_medioc_ocup18m",
    "t_supec_ocup18m",
    "t_renda_todos_trabalhos",
    "t_nremunerado_18m",
]

# Checar NM_SUBDIST in df_ivs_an.nome_udh
dados_sem_metrica = []
for col_iv in cols_ivs:
    try:
        df_in[col_iv] = None
        for subd in pd.unique(df_in.NM_SUBDIST):
            dt_ivs_aux = df_ivs_an[[subd in i for i in df_ivs_an.nome_udh]]
            if not dt_ivs_aux.empty:
                ivs_end = dt_ivs_aux[[subd in i for i in dt_ivs_aux.nome_udh]][
                    col_iv
                ].mean()
                df_in.loc[df_in.NM_SUBDIST == subd, col_iv] = ivs_end

        nm_subdist_nan = pd.unique(df_in[df_in[col_iv].isna()].NM_SUBDIST)

        # Para cada CS do df_in com NM_SUBDIST em nm_subdist_nan
        for subd in nm_subdist_nan:
            # Seleciona as linhas do df_in com esse NM_SUBDIST
            mask_cs = df_in.NM_SUBDIST == subd
            cs_sem_ivs = df_in[mask_cs]
            # Para cada CS sem IVS
            for idx, row in cs_sem_ivs.iterrows():
                lat_cs = row["Latitude"]
                lon_cs = row["Longitude"]
                # Seleciona todos os pontos do df_in que já têm IVS atribuído (não nulo)
                df_com_ivs = df_in[df_in[col_iv].notna()]
                if df_com_ivs.empty:
                    continue  # não há pontos com IVS ainda, pular
                # Calcula as distâncias haversine para todos os pontos com IVS
                dists = df_com_ivs.apply(
                    lambda r: haversine(lon_cs, lat_cs, r["Longitude"], r["Latitude"]),
                    axis=1,
                )
                # Encontra o índice do ponto mais próximo
                idx_min = dists.idxmin()
                # Atribui o valor de IVS do ponto mais próximo
                ivs_mais_prox = df_com_ivs.loc[idx_min, col_iv]
                df_in.at[idx, col_iv] = ivs_mais_prox
    except:
        dados_sem_metrica.append(col_iv)


df_in.to_excel("Dados_demanda_demografia_ivs.xlsx")
