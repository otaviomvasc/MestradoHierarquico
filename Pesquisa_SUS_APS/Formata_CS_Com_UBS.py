# %%
import pandas as pd
import numpy as np
import geopandas as gpd
from shapely.geometry import Point

pd.set_option("display.max_columns", 500)
# %%
# Carregar dados dos setores censitários
setores = gpd.read_file(
    r"C:\Users\marce\OneDrive\Área de Trabalho\Repo_Dados_MAPA\mapas\shapes\setores_ligth_processado.gpkg"
)
setores_proj = setores.to_crs(epsg=31983)
setores["id_setor"] = setores["id_setor"].astype(int)

# Carregar dados de correspondência Setor-APS
path_sc_jf = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Pesquisa_SUS_APS\Setor-Censitario-APS.xlsx"
df_SC_jf = pd.read_excel(path_sc_jf, sheet_name="dados")
# %%
# Renomear colunas usando primeira linha
df_SC_jf.columns = df_SC_jf.iloc[0]
df_SC_jf = df_SC_jf.drop(df_SC_jf.index[0]).reset_index(drop=True)
setores_proj["CD_setor"] = setores_proj["id_setor"].astype(int)
# Merge com geometrias dos setores
df_merge = df_SC_jf.merge(
    setores_proj[["CD_setor", "geometry"]],
    on="CD_setor",
    how="left",
)

# %%
# Carregar dados das UBS
path_dados_UBS = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Pesquisa_SUS_APS\v01_UBS_BRASIL.xlsx"
df_ubs = pd.read_excel(path_dados_UBS, sheet_name="v01_UBS_Brasil_new")
cols_used = ["NU_LATITUDE", "NU_LONGITUDE", "CO_UNIDADE"]
df_ubs_end = df_ubs[cols_used].copy()


# Função para limpar coordenadas (formato brasileiro com vírgula)
def limpar_coordenada(coord):
    if pd.isna(coord):
        return None
    try:
        return float(str(coord).replace(",", "."))
    except (ValueError, TypeError):
        return None


# Limpar coordenadas
df_ubs_end["NU_LONGITUDE"] = df_ubs_end["NU_LONGITUDE"].apply(limpar_coordenada)
df_ubs_end["NU_LATITUDE"] = df_ubs_end["NU_LATITUDE"].apply(limpar_coordenada)

# Log de UBS removidas
ubs_invalidas = (
    len(df_ubs_end) - df_ubs_end[["NU_LONGITUDE", "NU_LATITUDE"]].dropna().shape[0]
)
print(f"⚠️  UBS com coordenadas inválidas removidas: {ubs_invalidas}")

# Remover coordenadas inválidas
df_ubs_end = df_ubs_end.dropna(subset=["NU_LONGITUDE", "NU_LATITUDE"])
print(f"✓ UBS válidas para análise: {len(df_ubs_end)}")

# Converter UBS para GeoDataFrame
df_ubs_end["geometry"] = df_ubs_end.apply(
    lambda row: Point(row["NU_LONGITUDE"], row["NU_LATITUDE"]), axis=1
)
ubs_gdf = gpd.GeoDataFrame(df_ubs_end, geometry="geometry", crs="EPSG:4326")
ubs_proj = ubs_gdf.to_crs(epsg=31983)
# %%
# Preparar GeoDataFrame dos setores
setores_geom = gpd.GeoDataFrame(
    df_merge[["CD_setor", "geometry"]], geometry="geometry", crs=ubs_proj.crs
)
# %%
# Spatial Join - verificar UBS dentro dos setores
resultado_spatial = gpd.sjoin(ubs_proj, setores_geom, how="left", predicate="within")

# Agrupar por setor - LISTA com todas as UBS
ubs_por_setor = (
    resultado_spatial.groupby("CD_setor")
    .agg({"CO_UNIDADE": lambda x: x.tolist()})  # Lista de todas UBS no setor
    .reset_index()
)
# %%
# Renomear coluna
ubs_por_setor = ubs_por_setor.rename(columns={"CO_UNIDADE": "CO_UNIDADE_UBS_AUX"})

# Adicionar quantidade de UBS
ubs_por_setor["qtd_ubs"] = ubs_por_setor["CO_UNIDADE_UBS_AUX"].apply(len)

# Merge com dataframe original
df_merge_final = df_merge.merge(
    ubs_por_setor[["CD_setor", "CO_UNIDADE_UBS_AUX", "qtd_ubs"]],
    on="CD_setor",
    how="left",
)

# Preencher setores sem UBS com lista vazia
df_merge_final["CO_UNIDADE_UBS_AUX"] = df_merge_final["CO_UNIDADE_UBS_AUX"].apply(
    lambda x: x if isinstance(x, list) else []
)
df_merge_final["qtd_ubs"] = df_merge_final["qtd_ubs"].fillna(0).astype(int)


# %%
# Deixei o método pronto para, se necessario, juntar duas UBS no mesmo setor!
def define_CO_UBS_UNIDADE_FINAL(unidades):
    if len(unidades) == 0:
        return 0
    if len(unidades) == 1:
        return unidades[0]
    else:
        return unidades


# %%
df_merge_final["CO_UNIDADE_UBS"] = df_merge_final["CO_UNIDADE_UBS_AUX"].apply(
    define_CO_UBS_UNIDADE_FINAL
)


# %%
# Estatísticas finais
print(f"\n📊 RESULTADOS:")
print(f"Total de setores: {len(df_merge_final)}")
print(f"Setores com UBS: {len(df_merge_final[df_merge_final['qtd_ubs'] > 0])}")
print(f"Setores sem UBS: {len(df_merge_final[df_merge_final['qtd_ubs'] == 0])}")
print(f"Total de UBS mapeadas: {df_merge_final['qtd_ubs'].sum()}")

# Exemplo de setores com múltiplas UBS
multiplas = df_merge_final[df_merge_final["qtd_ubs"] > 1]
if len(multiplas) > 0:
    print(f"\n⚡ Setores com múltiplas UBS: {len(multiplas)}")
    print(
        f"   Exemplo: {multiplas[['CD_setor', 'CO_UNIDADE_UBS', 'qtd_ubs']].head(3).to_dict('records')}"
    )
# %%
df_merge_final = df_merge_final.drop(["CO_UNIDADE_UBS_AUX", "geometry"], axis=1)
# %%
# df_export = df_merge_final[['SETOR', "CO_UNIDADE_UBS", 'geometry']]
# Exportar df_merge_final para a planilha no path_sc_jf na aba "dados"
with pd.ExcelWriter(
    path_sc_jf, mode="a", if_sheet_exists="replace", engine="openpyxl"
) as writer:
    df_merge_final.to_excel(writer, sheet_name="setores_com_ubs", index=False)

# %%
df_merge_final.to_csv("Setor-censitario_dados.csv")

# %%
