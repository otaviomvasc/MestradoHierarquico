# %%
import pandas as pd
import numpy as np
import geopandas as gpd
import json


# %%
df = pd.read_excel(
    r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\dados_PRONTOS_para_modelo_OTM\instalacoes_secundarias_Contagem.xlsx"
)


# Função para extrair latitude e longitude de uma string POINT
def extrair_coordenadas_ponto(string_ponto):
    """
    Extrai latitude e longitude de uma string no formato 'POINT (longitude latitude)'

    Args:
        string_ponto (str): String no formato 'POINT (-44.0306576 -19.9339304)'

    Returns:
        tuple: (latitude, longitude)
    """
    # Remove 'POINT (' do início e ')' do final
    coordenadas_str = string_ponto.replace("POINT (", "").replace(")", "")

    # Divide a string pelos espaços e converte para float
    coordenadas = coordenadas_str.split()
    longitude = float(coordenadas[0])
    latitude = float(coordenadas[1])

    return latitude, longitude


df["latitude"] = df.location.apply(lambda x: extrair_coordenadas_ponto(x)[0])
df["longitude"] = df.location.apply(lambda x: extrair_coordenadas_ponto(x)[1])

df.to_excel("instalacoes_secundarias_Contagem_FIM.xlsx")
# Exemplo de uso:
# string_exemplo = 'POINT (-44.0306576 -19.9339304)'
# latitude, longitude = extrair_coordenadas_ponto(string_exemplo)
# print(f"Latitude: {latitude}")
# print(f"Longitude: {longitude}")


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
