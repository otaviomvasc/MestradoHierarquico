import streamlit as st
import pandas as pd
import plotly.express as px
import folium
from streamlit_folium import st_folium
from pos_OTM_END import posOTMFinal


st.set_page_config(page_title="OTM Saúde - Dashboard", layout="wide")


@st.cache_data(show_spinner=False)
def load_model(path_baseline: str, dicts_paths: dict) -> posOTMFinal:
    return posOTMFinal(path_baseline, dicts_paths)


st.title("Dashboard de Cenários - OTM Saúde")

# Inputs de arquivos
with st.sidebar:
    st.header("Arquivos")
    path_baseline = st.text_input(
        "Caminho do baseline (.xlsx)",
        value="C:/Users/marce/OneDrive/Área de Trabalho/MestradoHierarquico/resultados_alocacao_baseline.xlsx",
    )

    st.subheader("Cenários (nome → caminho .xlsx)")
    default_paths = {
        "Resultados_COBERTURA_MAXIMA_6": "C:/Users/marce/OneDrive/Área de Trabalho/MestradoHierarquico/Resultados_COBERTURA_MAXIMA_6.xlsx",
        "Resultados_COBERTURA_MAXIMA_7": "C:/Users/marce/OneDrive/Área de Trabalho/MestradoHierarquico/Resultados_COBERTURA_MAXIMA_7.xlsx",
        "Resultados_COBERTURA_MAXIMA_8": "C:/Users/marce/OneDrive/Área de Trabalho/MestradoHierarquico/Resultados_COBERTURA_MAXIMA_8.xlsx",
    }
    text = st.text_area(
        "Cole um dicionário Python (chave: nome do cenário, valor: caminho)",
        value=str(default_paths),
        height=120,
    )
    try:
        dicts_paths = eval(text)
        assert isinstance(dicts_paths, dict)
    except Exception:
        st.stop()

model = load_model(path_baseline, dicts_paths)
cenarios = list(dicts_paths.keys())
cen = st.selectbox("Cenário", options=cenarios)

tab1, tab2, tab3 = st.tabs(["Mapa", "Fluxo - Gráficos", "Cobertura total"])

with tab1:
    mapa = model.plota_mapa_cobertura_OTM(cen)
    st_folium(mapa, width=None, height=680)

with tab2:
    df = model.dfs_otm_fluxo_equipes[cen]
    df = df[(df.Total_Equipes > 0) | (df.Tipo_UBS == "Real")].reset_index()

    col1, col2 = st.columns(2)
    with col1:
        fig = px.histogram(df, x="Valor_Variavel_Fluxo", nbins=30, marginal="box")
        fig.update_layout(template="plotly_white", title="Distribuição do Fluxo")
        st.plotly_chart(fig, use_container_width=True)
    with col2:
        fig = px.box(df, x="Tipo_UBS", y="Valor_Variavel_Fluxo", points="all")
        fig.update_layout(template="plotly_white", title="Fluxo por Tipo de UBS")
        st.plotly_chart(fig, use_container_width=True)

    fig = px.scatter(
        df,
        x="Total_Equipes",
        y="Valor_Variavel_Fluxo",
        color="Tipo_UBS",
        size="Quantidade_Equipes_CNES",
        hover_data=["UBS", "Quantidade_Equipes_CNES", "Total_Equipes"],
        trendline="ols",
        template="plotly_white",
        title="Fluxo vs Total de Equipes",
    )
    st.plotly_chart(fig, use_container_width=True)

with tab3:
    model.calcula_cobertura_total()
    cob = model.coberturas_totais
    cob_df = pd.DataFrame(
        {"cenario": list(cob.keys()), "cobertura(%)": list(cob.values())}
    )
    fig = px.bar(cob_df, x="cenario", y="cobertura(%)", text="cobertura(%)")
    fig.update_traces(textposition="outside")
    fig.update_layout(template="plotly_white", yaxis_range=[0, 100])
    st.plotly_chart(fig, use_container_width=True)
