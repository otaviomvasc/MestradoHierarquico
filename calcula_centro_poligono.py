# %%
import pandas as pd
import numpy as np
import geopandas as gpd

# %%
# path_dados_fim = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_brutos_demanda\Setor-Censitario-APS.xlsx"
setores = gpd.read_file(
    r"C:\Users\marce\OneDrive\Área de Trabalho\Repo_Dados_MAPA\mapas\shapes\setores_ligth_processado.gpkg"
)

# dados_fim = pd.read_excel(path_dados_fim, sheet_name="dados")
setores["id_setor"] = setores["id_setor"].astype(int)

# %%
# Calcular o centroide de cada MultiPolygon na coluna 'geometry'
# Reprojetar para um CRS projetado adequado antes de calcular o centroide
# Exemplo: UTM zone 23S (EPSG:31983) para o Brasil, ajuste conforme necessário para sua área
setores_proj = setores.to_crs(epsg=31983)
setores["centroide"] = setores_proj.geometry.centroid.to_crs(setores.crs)

# Separar as coordenadas x (longitude) e y (latitude) do centroide em colunas separadas
setores["longitude"] = setores["centroide"].x
setores["latitude"] = setores["centroide"].y
setores["Coordendas_lat_long"] = setores.apply(
    lambda x: (x.latitude, x.longitude), axis=1
)
# %%

# df_merge = dados_fim[["CD_s setor"]].merge(
# setores[["id_setor", "Coordendas_lat_long"]],
# left_on="CD_setor",
# right_on="id_setor",
# how="left",
# )
# %%
# df_merge.to_excel("Dados_CS_com_coords.xlsx")
# %%
