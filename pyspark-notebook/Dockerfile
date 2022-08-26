# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.
ARG ADLS_ACCOUNT_NAME
ARG ADLS_ACCOUNT_KEY
ARG ACR_NAME
ARG WORK_IMAGE
ARG ACR_PULL_SECRET
ARG JHUB_NAMESPACE
ARG SPARK_NDOE_POOL
ARG SERVICE_ACCOUNT
ARG USER_FS_PVC
ARG PROJECT_FS_PVC
ARG LAKEHOUSE_PVC

FROM jupyter/scipy-notebook:python-3.9.13 as system

LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"

USER root

RUN apt-get -y update && \
    apt-get install --no-install-recommends -y openjdk-11-jre-headless ca-certificates-java && \
    rm -rf /var/lib/apt/lists/*

# Install Tools
RUN apt-get update && apt-get install -y curl ssh git vim gcc

################################################################################
# spark builder
################################################################################

FROM ${WORK_IMAGE} as builder

################################################################################
# merge
################################################################################
FROM system

ARG ADLS_ACCOUNT_NAME
ARG ADLS_ACCOUNT_KEY
ARG ACR_NAME
ARG WORK_IMAGE
ARG ACR_PULL_SECRET
ARG JHUB_NAMESPACE
ARG SPARK_NDOE_POOL
ARG SERVICE_ACCOUNT
ARG USER_FS_PVC
ARG PROJECT_FS_PVC
ARG LAKEHOUSE_PVC

USER $NB_UID
## Install python3 packages
RUN mamba install --quiet --yes \
	pyarrow \
	pandas \
	numpy \
	snappy \
	Cython \
	azure-storage-file-datalake \
	junit-xml \
	adal \
	boto3 \
    s3fs \
	graphframes \
	findspark \
	pyspark==3.2.1 \
	dataclasses-json \
    && conda clean --all -f -y  
RUN pip3 install delta-spark==2.0.0 timer sparksql-magic
COPY jupyter_notebook_config.py /etc/jupyter/

USER root
# Spark and Mesos config
ENV SPARK_HOME /opt/spark
ENV HADOOP_HOME /opt/hadoop
ENV PATH="${HADOOP_HOME}/bin:${PATH}"
ENV PATH="${SPARK_HOME}/bin:${PATH}"
ENV HADOOP_CONF_DIR "${HADOOP_HOME}/etc/hadoop"

RUN mkdir -p /opt/spark/conf
COPY spark-defaults.conf ${SPARK_HOME}/conf/spark-defaults.conf
COPY --from=builder /opt/spark ${SPARK_HOME}
COPY --from=builder /opt/hadoop ${HADOOP_HOME}

ENV JAVA_HOME=/usr
ENV PYTHONPATH="${SPARK_HOME}/python:${SPARK_HOME}/python/lib/py4j-*.zip:${SPARK_HOME}/python/lib/pyspark.zip"
ENV PYSPARK_PYTHON=/opt/conda/bin/python
ENV SPARK_DIST_CLASSPATH="/opt/hadoop/etc/hadoop:/opt/hadoop/share/hadoop/common/lib/*:/opt/hadoop/share/hadoop/common/*:/opt/hadoop/share/hadoop/hdfs:/opt/hadoop/share/hadoop/hdfs/lib/*:/opt/hadoop/share/hadoop/hdfs/*:/opt/hadoop/share/hadoop/mapreduce/lib/*:/opt/hadoop/share/hadoop/mapreduce/*:/opt/hadoop/share/hadoop/yarn:/opt/hadoop/share/hadoop/yarn/lib/*:/opt/hadoop/share/hadoop/yarn/*:/opt/hadoop/share/hadoop/tools/*:/opt/hadoop/share/hadoop/tools/lib/*"
ENV SPARK_EXTRA_CLASSPATH="/opt/hadoop/etc/hadoop:/opt/hadoop/share/hadoop/common/lib/*:/opt/hadoop/share/hadoop/common/*:/opt/hadoop/share/hadoop/hdfs:/opt/hadoop/share/hadoop/hdfs/lib/*:/opt/hadoop/share/hadoop/hdfs/*:/opt/hadoop/share/hadoop/mapreduce/lib/*:/opt/hadoop/share/hadoop/mapreduce/*:/opt/hadoop/share/hadoop/yarn:/opt/hadoop/share/hadoop/yarn/lib/*:/opt/hadoop/share/hadoop/yarn/*:/opt/hadoop/share/hadoop/tools/*:/opt/hadoop/share/hadoop/tools/lib/*"
# ENV MESOS_NATIVE_LIBRARY /usr/local/lib/libmesos.so
ENV SPARK_OPTS --driver-java-options=-Xms1024M --driver-java-options=-Xmx4096M --driver-java-options=-Dlog4j.logLevel=info
ENV HADOOP_USER_NAME=root

# RUN pip3 install jupyter-server-proxy \
#   && jupyter serverextension enable --sys-prefix jupyter_server_proxy

COPY jupyter-server-proxy /opt/jupyter-server-proxy
RUN cd /opt && chown -R jovyan jupyter-server-proxy
COPY jupyter-sparkui-proxy /opt/jupyter-sparkui-proxy
RUN cd /opt && chown -R jovyan jupyter-sparkui-proxy

USER $NB_UID
RUN cd /opt/jupyter-server-proxy \
    && pip3 install . 
RUN cd /opt/jupyter-sparkui-proxy \
    && pip3 install .

USER root
RUN echo "spark.kubernetes.namespace                                                                ${JHUB_NAMESPACE}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.node.selector.agentpool                                                  ${SPARK_NDOE_POOL}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.container.image                                                          ${WORK_IMAGE}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.container.image.pullSecrets                                              ${ACR_PULL_SECRET}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.authenticate.driver.serviceAccountName                                   ${SERVICE_ACCOUNT}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.hadoop.fs.azure.account.auth.type.${ADLS_ACCOUNT_NAME}.dfs.core.windows.net         SharedKey" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.hadoop.fs.azure.account.key.${ADLS_ACCOUNT_NAME}.dfs.core.windows.net               ${ADLS_ACCOUNT_KEY}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.hadoop.fs.azure.account.auth.type.${ADLS_ACCOUNT_NAME}.blob.core.windows.net        SharedKey" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.hadoop.fs.azure.account.key.${ADLS_ACCOUNT_NAME}.blob.core.windows.net              ${ADLS_ACCOUNT_KEY}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.executor.volumes.persistentVolumeClaim.user-claim.options.claimName      ${USER_FS_PVC}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.executor.volumes.persistentVolumeClaim.project-claim.options.claimName   ${PROJECT_FS_PVC}" >> ${SPARK_HOME}/conf/spark-defaults.conf \
    && echo "spark.kubernetes.executor.volumes.persistentVolumeClaim.lakehouse-claim.options.claimName ${LAKEHOUSE_PVC}" >> ${SPARK_HOME}/conf/spark-defaults.conf

USER $NB_UID

EXPOSE 8888
