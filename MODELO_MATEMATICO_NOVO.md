# Modelo Matemático do Problema de Otimização em Saúde Hierárquica

## 1. Modelo de Minimização de Custos

### Conjuntos
- **D**: Conjunto de pontos de demanda  
- **S₁**: Unidades primárias (n1)  
- **S₂**: Unidades secundárias (n2)  
- **S₃**: Unidades terciárias (n3)  
- **S₁ᶜᵃⁿᵈ**: Unidades primárias candidatas  
- **S₁ʳᵉᵃˡ**: Unidades primárias reais  
- **S₂ʳᵉᵃˡ**: Unidades secundárias reais
- **S₃ʳᵉᵃˡ**: Unidades terciárias reais
- **E₁, E₂, E₃**: Conjuntos de equipes por nível  
- **P**: Conjunto de perfis populacionais
- **Ω₁(d)**: Domínio de alocação primária para d  
- **Ω₂(n₁)**: Domínio de n2 para n1  
- **Ω₃(n₂)**: Domínio de n3 para n2  

### Parâmetros
- **dem₍d₎**: Demanda no ponto d  
- **cap₍eq₎**: Capacidade máxima por equipe eq  
- **S_custo_fixo_n1, S_custo_equipe_n1, S_custo_variavel_n1**: custos  
- **percent_n1_n2, percent_n2_n3**: percentuais de encaminhamento  
- **Cap_n1, Cap_n2, Cap_n3**: capacidades máximas  
- **S_capacidade_CNES_n1**: equipes existentes  
- **Matriz_Dist_n1, Matriz_Dist_n2, Matriz_Dist_n3**: matrizes de distância
- **custo_deslocamento**: custo unitário de transporte
- **Custo_abertura_n1, Custo_abertura_n2, Custo_abertura_n3**: custos de abertura
- **porcentagem_populacao[p]**: percentual da população por perfil p

### Variáveis
- **y_{d,n₁} ∈ {0,1}**: Alocação do ponto d à unidade n1  
- **z_{n₁} ∈ {0,1}**: Abertura da unidade n1  
- **x_{d,n₁,p} ≥ 0**: Fluxo de pacientes do perfil p de d para n1
- **f_{eq,n₁} ≥ 0**: Fluxo de equipes para n1  
- **x_{n₁,n₂,p} ≥ 0**: Fluxo de pacientes do perfil p de n1 para n2
- **x_{n₂,n₃,p} ≥ 0**: Fluxo de pacientes do perfil p de n2 para n3

### Função Objetivo

Minimizar o custo total do sistema:
```math
\min \sum_{n \in \{1,2,3\}} \left( C_{log}^n + C_{fixo}^{novos,n} + C_{fixo}^{exist,n} + C_{eq}^n + C_{var}^n \right)
```

Onde:
- **C_{log}^n**: Custo logístico do nível n
- **C_{fixo}^{novos,n}**: Custo fixo de novas unidades do nível n
- **C_{fixo}^{exist,n}**: Custo fixo de unidades existentes do nível n
- **C_{eq}^n**: Custo de equipes do nível n
- **C_{var}^n**: Custo variável do nível n

### Restrições

**Alocação primária**
```math
\sum_{n_1 \in \Omega_1(d)} y_{d,n_1} = 1, \quad \forall d \in D \tag{1}
```

**Fluxo de pacientes primário**
```math
x_{d,n_1,p} = y_{d,n_1} \cdot dem_d \cdot \pi_p, \quad \forall d \in D, n_1 \in \Omega_1(d), p \in P \tag{2}
```

**Abertura de unidades candidatas**
```math
\sum_{d \in D, p \in P: un \in \Omega_1(d)} x_{d,un,p} \leq z_{un} \cdot \sum_{d \in D} dem_d, \quad \forall un \in S_1^{cand} \tag{3}
```

**Capacidade das unidades**
```math
\sum_{d \in D, p \in P: n_1 \in \Omega_1(d)} x_{d,n_1,p} \leq Cap_{n_1}, \quad \forall n_1 \in S_1 \tag{4}
```

**Restrição de equipes (reais)**
```math
S\_capacidade\_CNES\_{un,eq} + f_{eq,un} = \sum_{d \in D, p \in P: un \in \Omega_1(d)} x_{d,un,p} \cdot cap_{eq}, \quad \forall eq \in E_1, un \in S_1^{real} \tag{5}
```

**Restrição de equipes (candidatas)**
```math
f_{eq,un} = \sum_{d \in D, p \in P: un \in \Omega_1(d)} x_{d,un,p} \cdot cap_{eq}, \quad \forall eq \in E_1, un \in S_1^{cand} \tag{6}
```

**Fluxo secundário**
```math
\sum_{n_2 \in \Omega_2(n_1)} x_{n_1,n_2,p} = \beta_{12} \cdot \sum_{d \in D: n_1 \in \Omega_1(d)} x_{d,n_1,p}, \quad \forall n_1 \in S_1, p \in P \tag{7}
```

**Fluxo terciário**
```math
\sum_{n_3 \in \Omega_3(n_2)} x_{n_2,n_3,p} = \beta_{23} \cdot \sum_{n_1 \in S_1: n_2 \in \Omega_2(n_1)} x_{n_1,n_2,p}, \quad \forall n_2 \in S_2, p \in P \tag{8}
```

**Restrição de equipes nível 2**
```math
S\_capacidade\_CNES\_{un,eq} + f_{eq,un} = \sum_{n_1 \in S_1, p \in P: un \in \Omega_2(n_1)} x_{n_1,un,p} \cdot cap_{eq}, \quad \forall eq \in E_2, un \in S_2^{real} \tag{9}
```

**Restrição de equipes nível 3**
```math
S\_capacidade\_CNES\_{un,eq} + f_{eq,un} = \sum_{n_2 \in S_2, p \in P: un \in \Omega_3(n_2)} x_{n_2,un,p} \cdot cap_{eq}, \quad \forall eq \in E_3, un \in S_3^{real} \tag{10}
```

**Domínios das variáveis**
```math
y_{d,n_1} \in \{0,1\}, \quad z_{n_1} \in \{0,1\}, \quad x_{d,n_1,p} \geq 0, \quad f_{eq,n_1} \geq 0, \quad x_{n_1,n_2,p} \geq 0, \quad x_{n_2,n_3,p} \geq 0
```

### Expressões de Custo

**Custo Logístico**
```math
C_{log}^n = \sum_{d \in D, un \in S_n, p \in P: un \in \Omega_n(d)} x_{d,un,p} \cdot dist_{d,un} \cdot custo\_transporte
```

**Custo Fixo de Novas Unidades**
```math
C_{fixo}^{novos,n} = \sum_{un \in S_n^{cand}} z_{un} \cdot Custo\_abertura_n
```

**Custo Fixo de Unidades Existentes**
```math
C_{fixo}^{exist,n} = \sum_{un \in S_n^{real}} S\_custo\_fixo_n
```

**Custo de Equipes**
```math
C_{eq}^n = \sum_{eq \in E_n, un \in S_n} f_{eq,un} \cdot S\_custo\_equipe_n[eq]
```

**Custo Variável**
```math
C_{var}^n = \sum_{d \in D, un \in S_n, p \in P: un \in \Omega_n(d)} x_{d,un,p} \cdot S\_custo\_variavel_n[p]
```

---

## 2. Modelo de Maximização de Cobertura

### Conjuntos e Parâmetros Adicionais
- **IVS_d**: Índice de Vulnerabilidade Social do ponto d
- **Orçamento**: Limite orçamentário total

### Variáveis Adicionais
- **p_{d,eq,n₁} ≥ 0**: População atendida do ponto d pela equipe eq na unidade n1

### Função Objetivo

Maximizar a população atendida ponderada pelo IVS:
```math
\max \sum_{d \in D} \sum_{eq \in E_1} \sum_{n_1 \in \Omega_1(d)} p_{d,eq,n_1} \cdot IVS_d
```

### Restrições Específicas

**População atendida limitada pela alocação**
```math
p_{d,eq,n_1} \leq y_{d,n_1} \cdot dem_d, \quad \forall d \in D, eq \in E_1, n_1 \in \Omega_1(d) \tag{11}
```

**Limite total de população atendida**
```math
\sum_{n_1 \in \Omega_1(d)} p_{d,eq,n_1} \leq dem_d, \quad \forall d \in D, eq \in E_1 \tag{12}
```

**Abertura de unidades candidatas**
```math
y_{d,s} \leq z_s, \quad \forall d \in D, s \in S_1^{cand}: s \in \Omega_1(d) \tag{13}
```

**Restrição orçamentária**
```math
C_{fixo}^{novos,1} + C_{fixo}^{exist,1} + C_{eq}^1 + C_{var}^1 \leq \text{Orçamento} \tag{14}
```

**Fluxo secundário (simplificado)**
```math
\sum_{n_2 \in \Omega_2(n_1)} x_{n_1,n_2} = \beta_{12} \cdot \sum_{d \in D, eq \in E_1: n_1 \in \Omega_1(d)} p_{d,eq,n_1}, \quad \forall n_1 \in S_1 \tag{15}
```

**Fluxo terciário (simplificado)**
```math
\sum_{n_3 \in \Omega_3(n_2)} x_{n_2,n_3} = \beta_{23} \cdot \sum_{n_1 \in S_1: n_2 \in \Omega_2(n_1)} x_{n_1,n_2}, \quad \forall n_2 \in S_2 \tag{16}
```

---

## Observações Importantes

1. **Flexibilidade dos Níveis**: O modelo suporta configurações com 1, 2 ou 3 níveis hierárquicos através das flags `flag_has_2_nivel` e `flag_has_3_nivel`.

2. **Tratamento de Equipes**: As equipes são tratadas diferentemente para unidades reais (que já possuem equipes) e candidatas (que precisam de novas equipes).

3. **Perfis Populacionais**: O modelo considera diferentes perfis populacionais (p ∈ P) com percentuais específicos.

4. **Matriz de Distância**: Cada nível possui sua própria matriz de distância para cálculo dos custos logísticos.

5. **Capacidades CNES**: As unidades reais já possuem equipes alocadas conforme dados do CNES, que são consideradas nas restrições. 