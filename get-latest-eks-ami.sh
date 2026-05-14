#!/bin/bash

# --- CATALOGO ---
echo "--------------------------------------------------------------------------------"
echo "Catálogo de SOs Otimizados para EKS:"
echo "1) Amazon Linux 2023 (Padrão)"
echo "2) Amazon Linux 2 (Legacy/Estável)"
echo "3) Bottlerocket (Segurança/Minimalista)"
echo "4) Ubuntu 22.04 (Canonical)"
echo "--------------------------------------------------------------------------------"

# --- ENTRADA DE DADOS ---
read -p "Escolha o SO (1-4) [Padrão: 1]: " OS_CHOICE
case $OS_CHOICE in
    2) OS_TYPE="amazon-linux-2" ;;
    3) OS_TYPE="bottlerocket" ;;
    4) OS_TYPE="ubuntu" ;;
    *) OS_TYPE="amazon-linux-2023" ;;
esac

read -p "Digite a versão alvo do EKS (ex: 1.34): " EKS_VERSION
if [ -z "$EKS_VERSION" ]; then
    echo "[ERRO] A versão do EKS é obrigatória."
    exit 1
fi

read -p "Arquitetura? (1 para x86_64, 2 para arm64) [Padrão: 1]: " INPUT_ARCH
case $INPUT_ARCH in
    2) ARCH="arm64" ;;
    *) ARCH="x86_64" ;;
esac

read -p "Região da AWS [Padrão: sa-east-1]: " INPUT_REGION
REGION=${INPUT_REGION:-sa-east-1}

# --- CONSTRUÇÃO DO PATH SSM ---
if [ "$OS_TYPE" == "bottlerocket" ]; then
    SSM_PATH="/aws/service/bottlerocket/aws-k8s-${EKS_VERSION}/${ARCH}/latest/image_id"
elif [ "$OS_TYPE" == "ubuntu" ]; then
    # A Canonical usa 'amd64' em vez de 'x86_64' nos seus paths
    UBUNTU_ARCH=$ARCH
    if [ "$ARCH" == "x86_64" ]; then
        UBUNTU_ARCH="amd64"
    fi
    SSM_PATH="/aws/service/canonical/ubuntu/eks/22.04/${EKS_VERSION}/stable/current/${UBUNTU_ARCH}/hvm/ebs-gp2/ami-id"
else
    SSM_PATH="/aws/service/eks/optimized-ami/${EKS_VERSION}/${OS_TYPE}/${ARCH}/standard/recommended/image_id"
fi

echo "--------------------------------------------------------------------------------"
echo "[INFO] Buscando AMI no SSM"
echo "[INFO] SO: $OS_TYPE | Versão: $EKS_VERSION | Arquitetura: $ARCH | Região: $REGION"
echo "--------------------------------------------------------------------------------"

AMI_ID=$(aws ssm get-parameter \
  --name "$SSM_PATH" \
  --region "$REGION" \
  --query "Parameter.Value" \
  --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$AMI_ID" ]; then
    echo "[SUCESSO] AMI Recomendada: $AMI_ID"
    echo "--------------------------------------------------------------------------------"
    echo "Configuração para EC2NodeClass (Karpenter):"
    
    # Ajuste automático do amiFamily dependendo do SO escolhido
    AMI_FAMILY="AL2023"
    if [ "$OS_TYPE" == "amazon-linux-2" ]; then AMI_FAMILY="AL2"; fi
    if [ "$OS_TYPE" == "bottlerocket" ]; then AMI_FAMILY="Bottlerocket"; fi
    if [ "$OS_TYPE" == "ubuntu" ]; then AMI_FAMILY="Ubuntu"; fi

    echo "amiFamily: $AMI_FAMILY"
    echo "amiSelectorTerms:"
    echo "  - id: \"$AMI_ID\""
else
    echo "[ERRO] AMI não encontrada. Verifique se a versão ($EKS_VERSION) já foi liberada pela AWS/Canonical para este SO."
fi