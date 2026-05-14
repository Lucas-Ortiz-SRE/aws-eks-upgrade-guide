# Guia de Atualização de Clusters AWS EKS

Clusters EKS que permanecem em versões fora do ciclo de suporte padrão passam automaticamente para o modelo de Extended Support, gerando cobranças adicionais significativas. Este repositório reúne scripts e documentação para conduzir atualizações de versão de forma segura e padronizada, garantindo que os clusters se mantenham dentro do suporte padrão e evitando custos desnecessários.

## Scripts Disponíveis

* **get-addon-recommendations.sh**: Script interativo que consulta a API da AWS para comparar as versões dos add-ons atualmente instalados no cluster com as versões recomendadas para a versão alvo do Kubernetes. O resultado é apresentado em formato de tabela, facilitando a tomada de decisão sobre quais componentes atualizar.

* **get-latest-eks-ami.sh**: Script interativo que consulta o AWS Systems Manager (SSM) Parameter Store para obter o ID da AMI otimizada mais recente para o EKS. Suporta diferentes sistemas operacionais (AL2023, AL2, Bottlerocket, Ubuntu) e arquiteturas (x86_64, arm64).

## Pré-requisitos

* AWS CLI configurada com credenciais válidas e permissões adequadas.
* Acesso ao cluster EKS via `kubectl` (kubeconfig atualizado).
* Ambiente Linux ou WSL para execução dos scripts.
* `jq` instalado para processamento de JSON.

## Passo a Passo da Atualização

### Passo 1: Atualização do Control Plane

A atualização do plano de controle deve ser realizada antes de qualquer outro componente do cluster.

1. No console da AWS, navegue até **EKS > Clusters > `[NOME_DO_CLUSTER]`**.
2. Na aba **Overview**, localize a versão atual do Kubernetes e clique em **Update cluster version**.
3. Selecione a versão `[VERSAO_ALVO]` e confirme a operação.
4. Aguarde o status do cluster retornar para **Active** antes de prosseguir.

> **Atenção:** Esta operação é sensível. Workloads podem sofrer reinicializações durante o processo e add-ons incompatíveis podem causar falhas no plano de controle ou nos nós. Não prossiga para os próximos passos até que o cluster esteja com status "Active".

### Passo 2: Atualização dos Add-ons

Com o cluster já na versão `[VERSAO_ALVO]`, utilize o script para identificar as versões recomendadas dos add-ons.

```bash
./get-addon-recommendations.sh
```

O script solicitará o nome do cluster e a versão alvo, retornando uma tabela semelhante ao exemplo abaixo:

| Add-on | Versão Atual | Sugestão Segura |
|--------|--------------|-----------------|
| aws-ebs-csi-driver | v1.35.0-eksbuild.1 | v1.37.0-eksbuild.1 |
| coredns | v1.11.3-eksbuild.2 | v1.12.0-eksbuild.1 |
| eks-pod-identity-agent | v1.3.4-eksbuild.1 | v1.3.4-eksbuild.1 (sem alteração) |
| kube-proxy | v1.31.3-eksbuild.1 | v1.32.0-eksbuild.2 |
| vpc-cni | v1.19.2-eksbuild.1 | v1.19.2-eksbuild.1 (sem alteração) |

Para cada add-on listado com versão diferente da atual, realize a atualização no console da AWS em **EKS > Clusters > `[NOME_DO_CLUSTER]` > Add-ons** ou via AWS CLI:

```bash
aws eks update-addon \
  --cluster-name [NOME_DO_CLUSTER] \
  --addon-name [NOME_DO_ADDON] \
  --addon-version [VERSAO_RECOMENDADA] \
  --resolve-conflicts OVERWRITE
```

### Passo 3: Atualização de Infraestrutura (Data Plane e AMIs)

Com o plano de controle e os add-ons atualizados, o próximo passo é atualizar as imagens dos nós de trabalho.

#### Etapa 1: Obter a nova AMI

Execute o script para consultar a AMI otimizada mais recente para a versão alvo:

```bash
./get-latest-eks-ami.sh
```

O script solicitará a versão do Kubernetes, o sistema operacional e a arquitetura desejados, retornando o ID da AMI (por exemplo, `[AMI_NOVA]`).

#### Etapa 2: Atualização para clusters com Karpenter

No recurso `EC2NodeClass`, substitua o ID da AMI antiga pelo novo no campo `amiSelectorTerms`:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: [NOME_DA_NODE_CLASS]
spec:
  amiSelectorTerms:
    - id: [AMI_NOVA]
  # ... demais configurações
```

Aplique a alteração:

```bash
kubectl apply -f ec2nodeclass.yaml
```

#### Etapa 3: Atualização para Managed Node Groups

1. No console da AWS, navegue até **EKS > Clusters > `[NOME_DO_CLUSTER]` > Compute**.
2. Localize o Node Group desejado e clique sobre ele.
3. Na seção **AMI release version**, clique em **Update**.
4. Selecione a nova versão da AMI e escolha o modo de atualização (Rolling update ou Force update).

#### Substituição dos nós

Após aplicar as alterações, os nós começarão a ser substituídos de forma gradual. Caso o processo demore ou seja necessário acelerar a migração, o operador pode forçar a evacuação de um nó específico:

1. No console do EKS, acesse o menu lateral **Nodes**.
2. Selecione o nó desejado.
3. Execute a ação **Drain** para migrar os workloads para outros nós disponíveis.

Alternativamente, via linha de comando:

```bash
kubectl drain [NOME_DO_NO] --ignore-daemonsets --delete-emptydir-data
```

## Observações Finais

* Sempre valide o plano de atualização em um ambiente de homologação antes de aplicar em produção.
* Mantenha backups dos manifestos e configurações do cluster antes de iniciar o processo.
* Monitore os logs e métricas do cluster durante toda a operação para identificar anomalias rapidamente.
