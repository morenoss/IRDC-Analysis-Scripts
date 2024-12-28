/*******************************************************************************
Script: Índice de Risco de Descumprimento Contratual (IRDC)
Autor: Moreno Souto Santiago
Licença: MIT
Última Atualização: 30/12/2024

Descrição:
Este script automatiza a análise logit para o artigo "Informação Contábil e Risco
de Descumprimento de Contratos no Setor Público Brasileiro". Inclui:
- Importação de dados
- Análise descritiva
- Transformação de variáveis
- Ajuste de modelos logit

Instruções:
1. Atualize os caminhos para os dados e resultados abaixo.
2. Certifique-se de ter o pacote `asdoc` instalado, caso deseje gerar relatórios.
3. Os dados utilizados no script devem estar no formato `Dados_IRDC.xlsx`.
*******************************************************************************/

/*******************************************************************************
PREPARAÇÃO - DEFINIÇÃO DE DIRETÓRIOS E CONFIGURAÇÕES INICIAIS
*******************************************************************************/
* Definir caminhos para os dados e resultados
local basedados     "C:\Users\kkbul\OneDrive - STJ- Superior Tribunal de Justiça\UnB\Mestrado em Governança e Inovação em Políticas Públicas\Projeto\Dados\Diretorio Stata\Github_IRDC\IRDC-Analysis-Scripts"
local resultados	"C:\Users\kkbul\OneDrive - STJ- Superior Tribunal de Justiça\UnB\Mestrado em Governança e Inovação em Políticas Públicas\Projeto\Dados\Diretorio Stata\Github_IRDC\IRDC-Analysis-Scripts\Resultados"

* Fechar qualquer log aberto
capture log close

* Limpar a memória do Stata
clear
set more off

* Iniciar log para registrar a execução
*log using "`resultados'/IRDC.log", replace text name ("IRDC_Resultados")

/*******************************************************************************
ETAPA 1 - IMPORTAÇÃO, ANÁLISE DESCRITIVA DAS VARIÁVEIS E TRANSFORMAÇÃO 
*******************************************************************************/
* Importar os dados do Excel
cd "`basedados'"
import excel "Dados_IRDC.xlsx", sheet("Tabela 1") firstrow clear


/******************************************************************************
1.1 - Executar estatísticas descritivas para todas as variáveis
*******************************************************************************/
summarize LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

/******************************************************************************
1.2 - Transformação de variáveis 
*******************************************************************************/
* Geração de variáveis dummies para o porte dos fornecedores
tabulate Porte, generate(Porte_)

* Geração de variáveis dummies para CNAE dos fornecedores
tabulate CNAE, generate(CNAE_)

* Geração de variáveis dummies para Natureza Jurídica dos fornecedores
tabulate NaturezaJuridica, generate(NaturezaJuridica_)

* Substituição de valores de ValorContrato por 1 onde o valor é 0 ou missing
replace vlrcontrato = 1 if vlrcontrato == 0 | vlrcontrato == .

* Geração do logaritmo natural do ValorContrato
gen log_vlrcontrato = log(vlrcontrato)

/*******************************************************************************
ETAPA 2 - IMPUTAÇÃO DOS VALORES FALTANTES (MISSING) COM A MÉDIA
*******************************************************************************/
* Lista de variáveis com dados faltantes para imputação
local imput_vars GiroAtivo MargOp MargLiq ROI ROE RecBruta LucroBruto LucroLiquido

* Imputação da média para valores faltantes (missing ou zero)
foreach var of local imput_vars {
    * Calcular a média da variável ignorando os valores missing e zero
    summarize `var' if `var' > 0
    local mean_val = r(mean)
    
    * Substituir os valores missing ou zero pela média
    replace `var' = `mean_val' if missing(`var') | `var' == 0
}
/******************************************************************************
ETAPA 3 - SEPARAÇÃO DOS DADOS EM CONJUNTOS DE TREINAMENTO E TESTE COM PROPORÇÕES EXATAS
*******************************************************************************/
* Definir uma seed para reprodutibilidade
set seed 12345

* Gerar uma variável aleatória uniforme entre 0 e 1
generate u = runiform()

* Ordenar aleatoriamente dentro de cada classe
sort FoiPenalizadoSTJ u

* Gerar índices de observação dentro de cada classe
by FoiPenalizadoSTJ: gen obs_no = _n
by FoiPenalizadoSTJ: gen total_obs = _N

* Calcular o ponto de corte para 80% das observações
by FoiPenalizadoSTJ: gen cutoff = ceil(0.80 * total_obs)

* Criar o indicador de treinamento
gen train = 0
replace train = 1 if obs_no <= cutoff

* Verificar as proporções em cada classe
tabulate FoiPenalizadoSTJ train

/******************************************************************************
Fornecer descrição básica da estrutura do conjunto de dados
*******************************************************************************/
describe


/*******************************************************************************
ETAPA 4 - ANÁLISE LOGIT

A variável dependente é 'FoiPenalizadoSTJ', do tipo binária.
Ela indica se o fornecedor foi penalizado pelo STJ (1) ou não (0).

As variáveis independentes serão divididas em variáveis contábeis e variáveis de controle.

*******************************************************************************/
* Definindo variáveis contábeis para o IRDC
local var_contabeis Porte_* LiqCorrente LiqGeral LiqCorAjust SolvGeral EndGeral CompEndivid IndepFin ImobilPL ImobRecNC PtpCapTerce GiroAtivo MargOp MargLiq ROI ROE 

* Definindo variáveis de controle para o IRDC
local var_controle CNAE_* NaturezaJuridica_* log_vlrcontrato QtdeCNAEsSecundarios IdadedeAnos QtePenalOutrosOrgaos

* Regressão logística para o IRDC com todas as variáveis (contábeis e de controle) no conjunto de treinamento
logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo completo
estimates store IRDCcompleto

/*******************************************************************************
Justificativa das Variáveis de Controle:

- **CNAE (Classificação Nacional de Atividades Econômicas)**: Diferentes setores econômicos possuem níveis distintos de regulação e riscos operacionais. Incluir o CNAE permite controlar os efeitos específicos de cada setor na probabilidade de penalização.

- **Natureza Jurídica**: Empresas com diferentes naturezas jurídicas têm estruturas legais e de governança distintas, o que pode influenciar a conformidade regulatória e o risco de penalidades.

- **log_vlrcontrato (Log do Valor do Contrato)**: Contratos de maior valor podem estar sujeitos a maior escrutínio e complexidade, aumentando o risco de penalidades. O logaritmo é usado para linearizar a relação.

- **QtdeCNAEsSecundarios (Quantidade de CNAEs Secundários)**: Indica o nível de diversificação das atividades da empresa. Empresas mais diversificadas podem ter estruturas mais complexas, afetando a gestão e a conformidade regulatória.

- **IdadedeAnos (Idade da Empresa em Anos)**: Empresas mais antigas podem ter processos mais estabelecidos e experiência acumulada, afetando positivamente a conformidade com normas e regulamentos.

- **QtePenalOutrosOrgaos (Quantidade de Penalidades Aplicadas por Outros Órgãos)**: Um histórico de penalidades pode indicar padrões de não conformidade, aumentando a probabilidade de novas penalizações.

Essas variáveis de controle são importantes para isolar o efeito das variáveis contábeis principais, garantindo que os resultados do modelo reflitam o impacto dos indicadores contábeis na probabilidade de penalização, independentemente de outros fatores externos.

*******************************************************************************/

/*******************************************************************************
Teste de Bondade de Ajuste de Hosmer-Lemeshow para o modelo completo
*******************************************************************************/
estat gof if e(sample), group(10) table

/*******************************************************************************
Tabela de Classificação para o modelo completo
*******************************************************************************/
estat class if e(sample)

/*******************************************************************************
Curva ROC para o modelo completo
*******************************************************************************/
lroc if e(sample)
graph export "lroc_IRDCcompleto.png", replace

* Sensibilidade e especificidade para o modelo completo
lsens if e(sample)
graph export "lsens_IRDCcompleto.png", replace

/*******************************************************************************
Regressão logística com seleção stepwise a 5% de significância no conjunto de treinamento
*******************************************************************************/
sw, pr(.05): logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo stepwise a 5%
estimates store IRDC05

* Teste de bondade de ajuste de Hosmer-Lemeshow para o modelo stepwise a 5%
estat gof if e(sample), group(10) table

* Tabela de classificação para o modelo stepwise a 5%
estat class if e(sample)

* Curva ROC para o modelo stepwise a 5%
lroc if e(sample)
graph export "lroc_IRDC05.png", replace

* Sensibilidade e especificidade para o modelo stepwise a 5%
lsens if e(sample)
graph export "lsens_IRDC05.png", replace

/*******************************************************************************
Regressão logística com seleção stepwise a 10% de significância no conjunto de treinamento
*******************************************************************************/
sw, pr(.1): logit FoiPenalizadoSTJ `var_contabeis' `var_controle' if train == 1

* Armazenar os resultados do modelo stepwise a 10%
estimates store IRDC10

* Teste de bondade de ajuste de Hosmer-Lemeshow para o modelo stepwise a 10%
estat gof if e(sample), group(10) table

* Tabela de classificação para o modelo stepwise a 10%
estat class if e(sample)

* Curva ROC para o modelo stepwise a 10%
lroc if e(sample)
graph export "lroc_IRDC10.png", replace

* Sensibilidade e especificidade para o modelo stepwise a 10%
lsens if e(sample)
graph export "lsens_IRDC10.png", replace

/*******************************************************************************
Teste de Razão de Verossimilhança entre os modelos (no conjunto de treinamento)
*******************************************************************************/
* Teste entre o modelo completo e o modelo a 5%
lrtest IRDCcompleto IRDC05

* Teste entre o modelo a 5% e o modelo a 10%
lrtest IRDC05 IRDC10

* Teste entre o modelo a 10% e o modelo completo
lrtest IRDC10 IRDCcompleto

/*******************************************************************************
Realização de Previsões com o Modelo IRDC10 no Conjunto de Teste
*******************************************************************************/
* Restaurar o modelo IRDC10
estimates restore IRDC10

* Verificar se as variáveis de previsão já existem e removê-las se necessário
capture drop prob_teste_sw10
capture drop predicted_class_teste_sw10

* Realizar a previsão das probabilidades no conjunto de teste
predict prob_teste_sw10 if train == 0

* Definir o cutoff padrão (por exemplo, 0.5) ou ajustar conforme necessário
gen predicted_class_teste_sw10 = prob_teste_sw10 >= 0.5 if train == 0

* Tabela de confusão no conjunto de teste
tabulate FoiPenalizadoSTJ predicted_class_teste_sw10 if train == 0

* Avaliar a performance no conjunto de teste cutoff padrão
estat class if train == 0, cutoff(0.5)

* Avaliar a performance no conjunto de teste
estat class if train == 0, cutoff(0.42)

* Curva ROC no conjunto de teste
roctab FoiPenalizadoSTJ prob_teste_sw10 if train == 0, graph
graph export "roc_IRDC10_teste.png", replace

/*******************************************************************************
Matriz de Correlação das variáveis contínuas do IRDC10
*******************************************************************************/

* Matriz de correlação para variáveis contínuas
ssc install asdoc

* Executar o comando asdoc e salvar o arquivo no local desejado
asdoc pwcorr LiqCorrente LiqGeral QtdeCNAEsSecundarios CompEndivid IndepFin ImobilPL log_vlrcontrato ROI QtePenalOutrosOrgaos, replace save(resultados/matriz_correlacao.doc)

/*******************************************************************************
FIM DO SCRIPT
*******************************************************************************/

log off
