#---------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
#---------------------------------------------------------------------------------------------

FROM python:3.6.4-alpine3.7

ARG CLI_VERSION

# Metadata as defined at http://label-schema.org
ARG BUILD_DATE

ENV JP_VERSION="0.1.3"
ENV KUBE_VERSION="v1.9.3"
ENV HELM_VERSION="v2.8.1"

LABEL maintainer="Microsoft" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.vendor="Microsoft" \
      org.label-schema.name="Azure CLI 2.0" \
      org.label-schema.version=$CLI_VERSION \
      org.label-schema.license="MIT" \
      org.label-schema.description="The Azure CLI 2.0 is the new Azure CLI and is applicable when you use the Resource Manager deployment model." \
      org.label-schema.url="https://docs.microsoft.com/en-us/cli/azure/overview" \
      org.label-schema.usage="https://docs.microsoft.com/en-us/cli/azure/install-az-cli2#docker" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/Azure/azure-cli.git" \
      org.label-schema.docker.cmd="docker run -v \${HOME}/.azure:/root/.azure -it microsoft/azure-cli:$CLI_VERSION"

WORKDIR azure-cli
COPY . /azure-cli

# bash gcc make openssl-dev libffi-dev musl-dev - dependencies required for CLI
# openssh - included for ssh-keygen
# ca-certificates
# wget - required for installing jp
# jq - we include jq as a useful tool
RUN apk add --no-cache bash openssh ca-certificates jq wget openssl git \
 && apk add --no-cache --virtual .build-deps gcc make openssl-dev libffi-dev musl-dev \
 && update-ca-certificates \
 && wget https://github.com/jmespath/jp/releases/download/${JP_VERSION}/jp-linux-amd64 -qO /usr/local/bin/jp \
 && chmod +x /usr/local/bin/jp \
 && wget https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kubectl -qO /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && wget https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz -qO /tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz \
 && tar -zxvf /tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz -C /tmp \
 && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf /tmp/linux-amd64 \
 && rm -f /tmp/helm-${HELM_VERSION}-linux-amd64.tar.gz \
 && chmod +x /usr/local/bin/helm \
# pip wheel - required for CLI packaging
# jmespath-terminal - we include jpterm as a useful tool
 && pip install --no-cache-dir --upgrade jmespath-terminal -r requirements.txt \
# 1. Build packages and store in tmp dir
# 2. Install the cli and the other command modules that weren't included
# 3. Temporary fix - install azure-nspkg to remove import of pkg_resources in azure/__init__.py (to improve performance)
 && /bin/bash -c 'TMP_PKG_DIR=$(mktemp -d); \
    for d in src/azure-cli src/azure-cli-core src/azure-cli-nspkg src/azure-cli-command_modules-nspkg src/command_modules/azure-cli-*/; \
    do cd $d; echo $d; python setup.py bdist_wheel -d $TMP_PKG_DIR; cd -; \
    done; \
    [ -d privates ] && cp privates/*.whl $TMP_PKG_DIR; \
    all_modules=`find $TMP_PKG_DIR -name "*.whl"`; \
    pip install --no-cache-dir $all_modules; \
    pip install --no-cache-dir --force-reinstall --upgrade azure-nspkg azure-mgmt-nspkg;' \
# Tab completion
 && cat /azure-cli/az.completion > ~/.bashrc \
 && find /usr/local \
    \( -type d -a -name test -o -name tests \) \
    -o \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
    -exec rm -rf '{}' + \
 && runDeps="$( \
    scanelf --needed --nobanner --recursive /usr/local \
        | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
        | sort -u \
        | xargs -r apk info --installed \
        | sort -u \
    )" \
 && apk add --virtual .rundeps $runDeps \
# Remove build dependencies
 && apk del .build-deps \
 && rm requirements.txt

WORKDIR /

CMD bash
