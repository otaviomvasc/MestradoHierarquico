# Modelo de Otimização para Alocação de Equipes de Saúde

## Conjuntos e Parâmetros

### Conjuntos
- $S_{n1}$: Conjunto de unidades básicas de saúde (UBS)
- $S_{n2}$: Conjunto de unidades secundárias (hospitais)
- $S_{n3}$: Conjunto de unidades terciárias (hospitais especializados)
- $S_D$: Conjunto de pontos de demanda (setores censitários)
- $S_{ESF}$: Conjunto de equipes ESF (Estratégia Saúde da Família)
- $S_{ESB}$: Conjunto de equipes ESB (Estratégia Saúde Bucal)
- $S_{ENASF}$: Conjunto de equipes ENASF (Equipe de Núcleo de Apoio à Saúde da Família)
- $S_{candidatos}$: Conjunto de locais candidatos para abertura de novas UBS
- $S_{reais}$: Conjunto de UBS já existentes

### Parâmetros
- $d_i$: Demanda populacional do setor censitário $i \in S_D$
- $IVS_i$: Índice de Vulnerabilidade Social do setor censitário $i \in S_D$
- $D_{ij}$: Distância entre UBS $i$ e $j$
- $D_{emulti}$: Distância máxima para alocação de UBS a ENASF (5 km)
- $\alpha$: Percentual de encaminhamento do nível 1 para o nível 2
- $\beta$: Percentual de encaminhamento do nível 2 para o nível 3
- $Cap_{ESF}$: Capacidade máxima por equipe ESF (3000 pessoas)
- $Cap_{ESB}$: Capacidade máxima por equipe ESB (3000 pessoas)
- $B$: Orçamento máximo disponível

## Variáveis de Decisão

### Variáveis Binárias de Abertura e Alocação
$$x_{i}^{n1} \in \{0,1\}, \quad \forall i \in S_{n1}$$
Variável binária que indica se a UBS $i$ está aberta.

$$y_{di} \in \{0,1\}, \quad \forall d \in S_D, i \in S_{n1}$$
Variável binária que indica se o setor censitário $d$ é atendido pela UBS $i$.

### Variáveis de Alocação de Equipes
$$z_{eq,i}^{ESF} \in \{0,1\}, \quad \forall eq \in S_{ESF}, i \in S_{n1}$$
Variável binária que indica se a equipe ESF $eq$ está alocada na UBS $i$.

$$z_{eq,i}^{ESB} \in \{0,1\}, \quad \forall eq \in S_{ESB}, i \in S_{n1}$$
Variável binária que indica se a equipe ESB $eq$ está alocada na UBS $i$.

$$z_{eq,i}^{ENASF} \in \{0,1\}, \quad \forall eq \in S_{ENASF}, i \in S_{n1}$$
Variável binária que indica se a equipe ENASF $eq$ está alocada na UBS $i$.

### Variáveis de População Atendida
$$p_{d,eq,i} \geq 0, \quad \forall d \in S_D, eq \in \{1,2\}, i \in S_{n1}$$
Variável contínua que representa a população do setor censitário $d$ atendida pela equipe $eq$ na UBS $i$.

### Variáveis de Alocação ENASF
$$a_{i,j} \in \{0,1\}, \quad \forall i \in S_{n1}, j \in S_{n1}: D_{ij} \leq D_{emulti}$$
Variável binária que indica se a UBS $i$ está alocada à UBS $j$ que possui ENASF.

### Variáveis Auxiliares para Linearização
$$w_{i,j} \geq 0, \quad \forall i \in S_{n1}, j \in S_{n1}: D_{ij} \leq D_{emulti}$$
Variável auxiliar para linearizar o produto $p_i \cdot a_{i,j}$, onde $p_i$ é a população ponderada atendida pela UBS $i$.

$$v_i \geq 0, \quad \forall i \in S_{n1}$$
Variável que representa a população ponderada atendida pela UBS $i$ através de ENASF.

### Variáveis de Fluxo Hierárquico
$$f_{i,j}^{n2} \geq 0, \quad \forall i \in S_{n1}, j \in S_{n2}$$
Fluxo de pacientes da UBS $i$ para a unidade secundária $j$.

$$f_{i,j}^{n3} \geq 0, \quad \forall i \in S_{n2}, j \in S_{n3}$$
Fluxo de pacientes da unidade secundária $i$ para a unidade terciária $j$.

## Restrições

### 1. Restrições de Atendimento
$$\sum_{i \in S_{n1}} y_{di} \leq 1, \quad \forall d \in S_D$$
Cada setor censitário pode ser atendido por no máximo uma UBS.

$$p_{d,eq,i} \leq y_{di} \cdot \max_{d' \in S_D} d_{d'}, \quad \forall d \in S_D, eq \in \{1,2\}, i \in S_{n1}$$
A população atendida por uma equipe em uma UBS só pode ser positiva se o setor censitário estiver alocado a essa UBS.

$$\sum_{i \in S_{n1}} p_{d,eq,i} \leq d_d, \quad \forall d \in S_D, eq \in \{1,2\}$$
A população total atendida de um setor censitário não pode exceder sua demanda.

### 2. Restrições de Alocação ENASF
$$\sum_{j: D_{ij} \leq D_{emulti}} a_{i,j} \leq 1, \quad \forall i \in S_{n1}$$
Cada UBS pode ser alocada a no máximo uma UBS com ENASF.

$$a_{i,j} \leq \sum_{eq \in S_{ENASF}} z_{eq,j}^{ENASF}, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$
Uma UBS só pode ser alocada a outra UBS se esta possuir pelo menos uma equipe ENASF.

$$a_{i,j} \leq x_i^{n1}, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$
$$a_{i,j} \leq x_j^{n1}, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$
A alocação entre UBSs só é possível se ambas estiverem abertas.

$$a_{i,i} \leq \sum_{eq \in S_{ENASF}} z_{eq,i}^{ENASF}, \quad \forall i \in S_{n1}$$
Uma UBS só pode se alocar a si mesma se possuir ENASF.

### 3. Restrições de Capacidade das Equipes
$$\sum_{eq \in S_{ESF}} z_{eq,i}^{ESF} \leq 4, \quad \forall i \in S_{n1}$$
Cada UBS pode ter no máximo 4 equipes ESF.

$$\sum_{eq \in S_{ENASF}} z_{eq,i}^{ENASF} \leq 1, \quad \forall i \in S_{n1}$$
Cada UBS pode ter no máximo 1 equipe ENASF.

$$\sum_{d \in S_D} p_{d,1,i} \leq \sum_{eq \in S_{ESF}} z_{eq,i}^{ESF} \cdot Cap_{ESF}, \quad \forall i \in S_{n1}$$
A população atendida por equipes ESF em uma UBS não pode exceder a capacidade total das equipes.

$$\sum_{d \in S_D} p_{d,2,i} \leq \sum_{eq \in S_{ESB}} z_{eq,i}^{ESB} \cdot Cap_{ESB}, \quad \forall i \in S_{n1}$$
A população atendida por equipes ESB em uma UBS não pode exceder a capacidade total das equipes.

### 4. Restrições de Alocação de Equipes
$$\sum_{eq \in S_{ESB}} z_{eq,i}^{ESB} = \sum_{eq \in S_{ESF}} z_{eq,i}^{ESF}, \quad \forall i \in S_{n1}$$
O número de equipes ESB deve ser igual ao número de equipes ESF em cada UBS.

$$\sum_{i \in S_{n1}} z_{eq,i}^{ESF} \leq 1, \quad \forall eq \in S_{ESF}$$
$$\sum_{i \in S_{n1}} z_{eq,i}^{ESB} \leq 1, \quad \forall eq \in S_{ESB}$$
$$\sum_{i \in S_{n1}} z_{eq,i}^{ENASF} \leq 1, \quad \forall eq \in S_{ENASF}$$
Cada equipe pode ser alocada em no máximo uma UBS.

### 5. Restrições de Abertura de Unidades
$$y_{di} \leq x_i^{n1}, \quad \forall d \in S_D, i \in S_{candidatos}$$
Setores censitários só podem ser atendidos por UBS candidatas se estas estiverem abertas.

$$x_i^{n1} = 1, \quad \forall i \in S_{reais}$$
UBS já existentes devem permanecer abertas.

### 6. Restrições de Fluxo Hierárquico
$$\sum_{j \in S_{n2}} f_{i,j}^{n2} = \alpha \sum_{d \in S_D, eq \in \{1,2\}} p_{d,eq,i}, \quad \forall i \in S_{n1}$$
O fluxo de pacientes do nível 1 para o nível 2 é proporcional à população atendida.

$$\sum_{j \in S_{n3}} f_{i,j}^{n3} = \beta \sum_{k \in S_{n1}} f_{k,i}^{n2}, \quad \forall i \in S_{n2}$$
O fluxo de pacientes do nível 2 para o nível 3 é proporcional ao fluxo recebido do nível 1.

### 7. Restrições de Linearização
$$w_{i,j} \leq \sum_{d \in S_D} p_{d,1,i} \cdot IVS_d, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$
$$w_{i,j} \leq a_{i,j} \cdot \sum_{d \in S_D} d_d, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$
$$w_{i,j} \geq \sum_{d \in S_D} p_{d,1,i} \cdot IVS_d - (1 - a_{i,j}) \cdot \sum_{d \in S_D} d_d, \quad \forall i \in S_{n1}, j: D_{ij} \leq D_{emulti}$$

$$v_j = \sum_{i: D_{ij} \leq D_{emulti}} w_{i,j}, \quad \forall j \in S_{n1}$$

### 8. Restrições de Orçamento
$$\sum_{eq \in S_{ESF}^{candidatas}, i \in S_{n1}} z_{eq,i}^{ESF} \cdot 30000 + \sum_{eq \in S_{ESB}^{candidatas}, i \in S_{n1}} z_{eq,i}^{ESB} \cdot 30000 + \sum_{eq \in S_{ENASF}^{candidatas}, i \in S_{n1}} z_{eq,i}^{ENASF} \cdot 40000 + \sum_{eq \in S_{ESF}^{reais}, i \in S_{n1}} D_{eq,i} \cdot z_{eq,i}^{ESF} \cdot 100 + \sum_{eq \in S_{ESB}^{reais}, i \in S_{n1}} D_{eq,i} \cdot z_{eq,i}^{ESB} \cdot 100 + \sum_{eq \in S_{ENASF}^{reais}, i \in S_{n1}} D_{eq,i} \cdot z_{eq,i}^{ENASF} \cdot 100 + \sum_{eq \in S_{ESF}, i \in S_{n1}} z_{eq,i}^{ESF} \cdot 32000 + \sum_{eq \in S_{ESB}, i \in S_{n1}} z_{eq,i}^{ESB} \cdot 32000 + \sum_{eq \in S_{ENASF}, i \in S_{n1}} z_{eq,i}^{ENASF} \cdot 90000 + \sum_{i \in S_{n1}} x_i^{n1} \cdot 1500 + \sum_{i \in S_{candidatos}} x_i^{n1} \cdot 10000 \leq 2B$$

## Função Objetivo

$$\max \sum_{d \in S_D, i \in S_{n1}} p_{d,1,i} \cdot IVS_d + \sum_{d \in S_D, i \in S_{n1}} p_{d,2,i} \cdot IVS_d + \sum_{i \in S_{n1}} v_i$$

A função objetivo maximiza a população atendida ponderada pelo Índice de Vulnerabilidade Social, considerando:
- População atendida por equipes ESF
- População atendida por equipes ESB  
- População atendida através de ENASF (via alocação de UBSs)

## Explicação das Restrições

### Restrições de Atendimento
Estas restrições garantem que cada setor censitário seja atendido por no máximo uma UBS e que a população atendida não exceda a demanda disponível. Elas são fundamentais para evitar sobreposição de atendimento e garantir que a capacidade seja respeitada.

### Restrições de Alocação ENASF
O modelo implementa um sistema hierárquico onde UBSs sem ENASF devem ser alocadas a UBSs que possuem ENASF, respeitando um raio máximo de 5 km. Isso simula a realidade do sistema de saúde brasileiro, onde equipes ENASF atendem múltiplas UBSs em uma região.

### Restrições de Capacidade
Cada tipo de equipe tem limitações específicas: máximo de 4 equipes ESF por UBS, 1 equipe ENASF por UBS, e capacidade de 3000 pessoas por equipe. A restrição de igualdade entre ESF e ESB garante que cada UBS tenha o mesmo número de equipes de ambos os tipos.

### Restrições de Fluxo Hierárquico
O modelo considera o encaminhamento de pacientes entre níveis de atenção, com percentuais fixos de encaminhamento do nível primário para secundário e do secundário para terciário.

### Linearização
O produto entre população atendida e alocação ENASF é linearizado usando variáveis auxiliares, permitindo que o modelo seja resolvido como um problema de programação linear inteira mista.

### Restrições de Orçamento
O modelo considera custos de contratação, realocação, operação mensal, abertura e manutenção de unidades, garantindo que o orçamento disponível seja respeitado.
