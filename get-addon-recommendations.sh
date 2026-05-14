#!/bin/bash

# --- ENTRADA DE DADOS ---
read -p "Digite o nome do cluster EKS: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
    echo "[ERRO] O nome do cluster é obrigatório."
    exit 1
fi

read -p "Digite a versão alvo do EKS (ex: 1.34): " TARGET_VERSION
if [ -z "$TARGET_VERSION" ]; then
    echo "[ERRO] A versão alvo é obrigatória."
    exit 1
fi

read -p "Digite a região da AWS (Padrão: sa-east-1): " input_region
REGION=${input_region:-sa-east-1}
export AWS_DEFAULT_REGION=$REGION

# --- FUNÇÃO DE COMPARAÇÃO ---
function version_ge() {
    v1=$(echo $1 | sed 's/[^0-9.]//g')
    v2=$(echo $2 | sed 's/[^0-9.]//g')
    [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" != "$v1" ] || [ "$v1" == "$v2" ]
}

echo "--------------------------------------------------------------------------------"
echo "[INFO] Planejamento de Upgrade ($REGION): $CLUSTER_NAME -> v$TARGET_VERSION"
echo "--------------------------------------------------------------------------------"
printf "%-25s | %-20s | %-20s\n" "Add-on" "Versão Atual" "Sugestão"
echo "--------------------------------------------------------------------------------"

# Captura os add-ons do cluster
ADDONS=$(aws eks list-addons --cluster-name $CLUSTER_NAME --query "addons" --output text)

if [ -z "$ADDONS" ]; then
    echo "[ERRO] Não foi possível encontrar add-ons. Verifique se o nome do cluster e a região estão corretos e se você tem permissão de acesso."
    exit 1
fi

for addon in $ADDONS; do
    # Versão atual no cluster
    CURRENT_VER=$(aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $addon \
        --query "addon.addonVersion" --output text)

    # Versão padrão recomendada pela AWS para a versão alvo
    STABLE_VER=$(aws eks describe-addon-versions --kubernetes-version $TARGET_VERSION --addon-name $addon \
        --query "addons[0].addonVersions[?compatibilities[0].defaultVersion==\`true\`].addonVersion" --output text)

    # Lógica de sugestão
    if version_ge "$CURRENT_VER" "$STABLE_VER" && [ "$addon" != "kube-proxy" ]; then
        SUGGESTION="$CURRENT_VER (Manter)"
    else
        SUGGESTION="$STABLE_VER (Atualizar)"
    fi

    # Ajuste específico para kube-proxy (deve bater com a versão do cluster)
    if [[ "$addon" == "kube-proxy" && ! "$STABLE_VER" == v$TARGET_VERSION* ]]; then
         STABLE_VER=$(aws eks describe-addon-versions --kubernetes-version $TARGET_VERSION --addon-name $addon \
            --query "addons[0].addonVersions[?startsWith(addonVersion, 'v$TARGET_VERSION')].addonVersion | [0]" --output text)
         SUGGESTION="$STABLE_VER (Atualizar)"
    fi

    printf "%-25s | %-20s | %-20s\n" "$addon" "$CURRENT_VER" "$SUGGESTION"
done