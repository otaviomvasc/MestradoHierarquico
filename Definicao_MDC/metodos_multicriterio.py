import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pyDecision.algorithm import electre_ii


class MCDA_SAUDE:
    def __init__(self, path_data_CS, municipio) -> None:
        self.path_data = path_data_CS
        self.municipio = municipio
        self.dataloader()

    def dataloader(self):
        # ler as tres abas do arquivo
        base_dados = pd.read_excel(self.path_data, "dados")
        dict_dados = pd.read_excel(self.path_data, "Dicionário")
        self.codigo_vars = [
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
            "V01007",
            "V01008",
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
            "V01031",
            "V01032",
            "V01033",
            "V01034",
            "V01035",
            "V01036",
            "V01037",
            "V01038",
            "V01039",
            "V01040",
            "V01041.1",
            "VPB01",
            "VPB02",
            "VPB03",
            "VPB04",
            "VPB05",
            "VPB06",
            "VPB07",
        ]

        self.df_dados = base_dados[base_dados.MUNICIPIO == self.municipio].reset_index(
            drop=True
        )

        for col in self.codigo_vars:
            self.df_dados[col] = self.df_dados[col].apply(
                lambda x: 0 if isinstance(x, str) else x
            )


# Funções utilitárias


def minmax_01(series, reverse=False):
    s = series.astype(float)
    mn, mx = s.min(), s.max()
    if mx == mn:
        x = np.zeros_like(s, dtype=float)
    else:
        x = (s - mn) / (mx - mn)
    if reverse:
        return 1.0 - x
    return x


def entropy_weights(X: pd.DataFrame) -> np.ndarray:
    # Calcula pesos por entropia para X (mesma direção: maior=pior)
    Z = X / (X.sum(axis=0) + 1e-12)
    n = len(X)
    k = 1.0 / np.log(n) if n > 1 else 0.0
    E = -k * (Z * np.log(Z + 1e-12)).sum(axis=0)
    d = 1 - E
    if d.sum() == 0:
        w = np.ones_like(d) / len(d)
    else:
        w = d / d.sum()
    return w.values


def smart_weighted_sum(X_norm: pd.DataFrame, weights: np.ndarray) -> np.ndarray:
    return (X_norm.values * weights).sum(axis=1)


def topsis(X_norm: pd.DataFrame, weights: np.ndarray) -> np.ndarray:
    # TOPSIS com X em [0,1], mesma direção (maior = pior)
    V = X_norm.values * weights
    ideal = np.zeros(V.shape[1])
    anti = np.ones(V.shape[1])
    d_pos = np.sqrt(((V - ideal) ** 2).sum(axis=1))
    d_neg = np.sqrt(((V - anti) ** 2).sum(axis=1))
    c = d_neg / (d_pos + d_neg + 1e-12)
    return c


def electre_tri_simplified(
    X_norm: pd.DataFrame,
    weights: np.ndarray,
    profiles: pd.DataFrame,
    veto: dict,
    concord_threshold=0.6,
):
    # Classificação em categorias com perfis (ordem crescente) e veto simples
    alt = X_norm.values
    W = np.array(weights, dtype=float)
    W = W / (W.sum() + 1e-12)
    prof = profiles.values
    n_profiles = prof.shape[0]
    labels = []
    for i in range(alt.shape[0]):
        a = alt[i, :]
        assigned = 0
        for b in range(n_profiles):
            p = prof[b, :]
            c = W[(a >= p)].sum()
            veto_hit = False
            for k_name, v_th in veto.items():
                j = list(X_norm.columns).index(k_name)
                if a[j] >= v_th:
                    veto_hit = True
                    break
            if (c >= concord_threshold) and (not veto_hit):
                assigned = b + 1
        labels.append(f"C{assigned+1}")
    return labels


if __name__ == "__main__":
    path_data = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Definicao_MDC\Setor-Censitario-APS.xlsx"
    municipio = "Contagem"
    MCDA_Contagem = MCDA_SAUDE(path_data_CS=path_data, municipio=municipio)
    # MCDA_Contagem.codigo_vars - MCDA_Contagem.df_dados
    df = MCDA_Contagem.df_dados.copy()
    X = df[
        [
            "V00008",
            "V01041",
            "V00111",
            "V00201",
            "V00238",
            "V00314",
            "V00401",
            "V00052",
            "V00901",
            "V00064",
        ]
    ].copy()

    X_norm = pd.DataFrame(
        {
            "V00008": minmax_01(X["V00008"], reverse=False),
            "V01041": minmax_01(X["V01041"], reverse=False),
            "V00111": minmax_01(X["V00111"], reverse=True),
            "V00201": minmax_01(X["V00201"], reverse=False),
            "V00238": minmax_01(X["V00238"], reverse=False),
            "V00314": minmax_01(X["V00314"], reverse=False),
            "V00401": minmax_01(X["V00401"], reverse=False),
            "V00052": minmax_01(X["V00052"], reverse=False),
            "V00901": minmax_01(X["V00901"], reverse=False),
            "V00064": minmax_01(X["V00064"], reverse=False),
        },
        index=df.index,
    )

    X_norm.head(10)

    w_entropy = entropy_weights(X_norm)
    w_entropy = w_entropy / w_entropy.sum()
    idx_mavt = smart_weighted_sum(X_norm, w_entropy)

    res_mavt = df[["CD_setor"]].copy()
    res_mavt["indice_mavt_entropy"] = idx_mavt
    res_mavt.sort_values("indice_mavt_entropy", ascending=False).head(10)

    # ==== 4) TOPSIS ====
    w_topsis = w_entropy.copy()
    score_topsis = topsis(X_norm, w_topsis)

    res_topsis = df[["CD_setor"]].copy()
    res_topsis["topsis"] = score_topsis
    res_topsis.sort_values("topsis", ascending=False).head(10)

    # ==== 5) ELECTRE‑TRI (simplificado) ====
    profiles = pd.DataFrame(
        [X_norm.quantile(0.40).values, X_norm.quantile(0.70).values],
        columns=X_norm.columns,
        index=["B1", "B2"],
    )

    veto = {"V00238": 0.15, "V00314": 0.25}

    classes = electre_tri_simplified(
        X_norm, w_entropy, profiles, veto, concord_threshold=0.6
    )

    res_electre = df[["CD_setor"]].copy()
    res_electre["classe_electre_tri"] = classes

    res_electre["classe_electre_tri"].value_counts().sort_index()

    out = df[["CD_setor"]].copy()
    out = out.join(X_norm)
    out = out.join(res_mavt.set_index("CD_setor"), on="CD_setor")
    out = out.join(res_topsis.set_index("CD_setor"), on="CD_setor")
    out = out.join(res_electre.set_index("CD_setor"), on="CD_setor")

    plt.figure()
    plt.scatter(out["indice_mavt_entropy"], out["topsis"])
    plt.xlabel("Índice MAVT (Entropia) — maior = pior")
    plt.ylabel("TOPSIS — maior = melhor")
    plt.title("Relação MAVT vs TOPSIS")
    plt.show()

    vc = out["classe_electre_tri"].value_counts().sort_index()
    plt.figure()
    plt.bar(vc.index, vc.values)
    plt.xlabel("Classe ELECTRE‑TRI (simplificado)")
    plt.ylabel("Número de setores")
    plt.title("Distribuição de classes")
    plt.show()
