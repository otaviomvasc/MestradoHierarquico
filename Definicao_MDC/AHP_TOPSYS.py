import numpy as np
import pandas as pd


class AHP:
    """
    Classe para cálculo de pesos pelo método Analytic Hierarchy Process (AHP).
    Se a matriz de comparações não for informada, atribui pesos iguais.

    Matriz de comparacoes (critério é mais importante que outro na escala de Saaty)
    1 - Quantidade de vezes que uma alterantiva é dominada ou domina outra
    2 - Calculo do autovetor para ordenar as caracteristicas avaliadas
    3 - Normaliza os autovetores
    4 - Calculo do indice de consistencia
    5 - Calculo da Razao de Consistencia

    """

    def __init__(self, criteria_names):
        self.criteria_names = criteria_names
        self.weights = None

    def fit(self, comparison_matrix=None):
        """
        Calcula os pesos.
        - comparison_matrix: matriz NxN com comparações par-a-par (opcional)
        """
        n = len(self.criteria_names)

        if comparison_matrix is None:
            # Pesos iguais se matriz não for informada
            self.weights = np.ones(n) / n
            return self.weights

        # Passo 1: Normalização da matriz
        column_sum = np.sum(comparison_matrix, axis=0)
        normalized_matrix = comparison_matrix / column_sum

        # Passo 2: Média das linhas -> pesos
        self.weights = np.mean(normalized_matrix, axis=1)

        # Passo 3: Cálculo da razão de consistência (CR)
        lambda_max = np.mean(
            np.sum(comparison_matrix * self.weights, axis=1) / self.weights
        )
        CI = (lambda_max - n) / (n - 1)
        RI_dict = {
            1: 0.00,
            2: 0.00,
            3: 0.58,
            4: 0.90,
            5: 1.12,
            6: 1.24,
            7: 1.32,
            8: 1.41,
            9: 1.45,
            10: 1.49,
        }
        RI = RI_dict.get(n, 1.49)  # valor aproximado se n > 10
        CR = CI / RI if RI != 0 else 0

        print(f"Lambda máximo: {lambda_max:.4f}")
        print(f"Índice de Consistência (CI): {CI:.4f}")
        print(f"Razão de Consistência (CR): {CR:.4f}")
        if CR > 0.1:
            print("⚠️ A matriz de comparações pode estar inconsistente.")

        return self.weights


class TOPSIS:
    """
    Classe para cálculo de ranking pelo método TOPSIS.
    Solucao ideal Positiva = Melhor em tudo
    Solucao ideal Negativa - Pior em tudo

    Distancia euclidiana para calculo do range entre A+ e A-
    Modulo do vetor normalizado de cada alternativa

    Ordenacao do modulo do vetor de cada alternativa.

    Quanto mais perto de A+, melhor.


    """

    def __init__(self, benefit_criteria=None):
        """
        benefit_criteria: lista booleana indicando se cada critério é de benefício (True) ou custo (False)
        """
        self.benefit_criteria = benefit_criteria
        self.scores = None
        self.ranking = None

    def fit(self, df, weights=None):
        """
        Executa o TOPSIS.
        - df: DataFrame apenas com colunas numéricas dos critérios
        - weights: vetor de pesos (opcional)
        """
        # Verifica se alguma coluna tem todos os valores iguais a zero
        cols_all_zero = [col for col in df.columns if (df[col] == 0).all()]
        idxs_col_zero = [
            i for i in range(len(df.columns)) if (df[df.columns[i]] == 0).all()
        ]
        if cols_all_zero:
            print(f"Removendo colunas com todos os valores zero: {cols_all_zero}")
            df = df.drop(columns=cols_all_zero)
            for idx in idxs_col_zero:
                self.benefit_criteria.pop(idx)
                if weights is not None:
                    weights = np.delete(weights, idx)

        data = df.values.astype(float)
        n, m = data.shape

        # Passo 1: Normalização vetorial
        norm = np.sqrt(np.sum(data**2, axis=0))
        normalized = data / norm

        # Passo 2: Aplicar pesos
        if weights is None:
            weights = np.ones(m) / m
        weighted = normalized * weights

        # Passo 3: Determinar solução ideal positiva e negativa
        ideal_positive = (
            np.max(weighted, axis=0)
            if self.benefit_criteria is None
            else np.array(
                [
                    (
                        np.max(weighted[:, j])
                        if self.benefit_criteria[j]
                        else np.min(weighted[:, j])
                    )
                    for j in range(m)
                ]
            )
        )
        ideal_negative = (
            np.min(weighted, axis=0)
            if self.benefit_criteria is None
            else np.array(
                [
                    (
                        np.min(weighted[:, j])
                        if self.benefit_criteria[j]
                        else np.max(weighted[:, j])
                    )
                    for j in range(m)
                ]
            )
        )

        # Passo 4: Calcular distâncias até as soluções ideais
        dist_positive = np.sqrt(np.sum((weighted - ideal_positive) ** 2, axis=1))
        dist_negative = np.sqrt(np.sum((weighted - ideal_negative) ** 2, axis=1))

        # Passo 5: Calcular escore de proximidade
        self.scores = dist_negative / (dist_positive + dist_negative)

        # Passo 6: Ranking (maior score → melhor posição)
        self.ranking = np.argsort(-self.scores)

        return self.scores, self.ranking


# ======== EXEMPLO DE USO ========

# 1. Carregar dados
file_path = r"C:\Users\marce\OneDrive\Área de Trabalho\MestradoHierarquico\Definicao_MDC\Dados_BRUTOS_CONTAGEM_FIM.xlsx"
df_original = pd.read_excel(file_path, sheet_name="DadosBrutoTotalPOP")
df_original = df_original.fillna(0)
# Drop linhas com todos os dados 0 e salve seus indices
criteria_cols = [c for c in df_original.columns if c != "CD_setor"]
zero_rows = df_original[criteria_cols].eq(0).all(axis=1)
zero_indices = df_original.index[zero_rows].tolist()  # Dados sem populacao
df = df_original[~zero_rows].reset_index(drop=True)
df_zero_pop = df_original[zero_rows].reset_index(drop=True)

# 2. Definir critérios (todas as colunas menos 'SETOR')

# criteria_cols = criteria_cols[:10]
# 3. AHP: criar e calcular pesos
ahp = AHP(criteria_cols)

# Exemplo: sem matriz de comparações → pesos iguais
weights_ahp = ahp.fit()
# sem variaveis de saude


# 4. TOPSIS: criar e calcular ranking
benefit_criteria = [
    True,
    True,
    True,
    False,
    True,
    True,
    True,
    True,
    True,
    True,
    False,
    False,
    False,
    False,
    False,
    False,
    False,
]

# benefit_criteria = benefit_criteria[:10]
topsis = TOPSIS(
    benefit_criteria=benefit_criteria
)  # aqui, todos os critérios são de benefício
scores, ranking = topsis.fit(df[criteria_cols], weights=weights_ahp)

# 5. Resultado final
df_result = df.copy()
df_result["Score_TOPSIS"] = scores
df_result = df_result.sort_values(by="Score_TOPSIS", ascending=False).reset_index(
    drop=True
)
df_result["Ranking"] = [i for i in range(len(df_result))]
df_zero_pop["Score_TOPSIS"] = min(df_result["Score_TOPSIS"])
df_zero_pop["Ranking"] = max(ranking)

df_result = pd.concat([df_result, df_zero_pop])


print(df_result.sort_values("Ranking"))
df_result.to_excel("Dados_rakiados-TOP_SYS_COMPLETO-DADOS-TOTAL-POP.xlsx")
