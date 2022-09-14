ARG SPARK_IMAGE=gcr.io/spark-operator/spark:v3.1.1
FROM ${SPARK_IMAGE}

ARG VERSION
ARG VCS_REF
ARG BUILD_DATE
ARG DEBIAN_FRONTEND noninteractive

ENV SPARK_VERSION 3.2.1
ENV HADOOP_VERSION 3.2.3
ENV REPO_URL http://central.maven.org/maven2
ENV ARCHIVE_URL http://archive.apache.org/dist

LABEL org.opencontainers.image.title="spark-py" \
      org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.description="base image for pyspark applications deploy on kubernetes cluster" \
      org.opencontainers.image.source="" \
      org.opencontainers.image.documentation="" \
      org.opencontainers.image.revison=${VCS_REF} \
      org.opencontainers.image.vendor="Just Modeling" \
      org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.authors="Ziang Jia <jiaza492@gmail.com>" \
      version.scala=${SCALA_VERSION} \
      version.spark=${SPARK_VERSION} \
      version.hadoop=${HADOOP_VERSION} \
      version.kubernetes-client=${KUBERNETES_CLIENT_VERSION}

USER root

# Install apt utils
RUN apt-get --allow-releaseinfo-change update --yes && \
    apt-get upgrade --yes && \
    apt-get install --yes -q --no-install-recommends \
    ca-certificates \
    fonts-liberation \
    locales \
    curl wget apt-utils git vim gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# ARG openjdk_version="11"
# RUN apt-get -y update && \
#     mkdir -p /usr/share/man/man1 && \
#     apt-get install --no-install-recommends -y openjdk-11-jre-headless ca-certificates-java && \
#     rm -rf /var/lib/apt/lists/*

# Hadoop Config
ENV HADOOP_HOME "/opt/hadoop"
RUN rm -rf ${HADOOP_HOME}/ \
   && cd /opt \
   && curl -sL --retry 3 "${ARCHIVE_URL}/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" | tar xz  \
   && chown -R root:root hadoop-${HADOOP_VERSION} \
   && ln -sfn hadoop-${HADOOP_VERSION} hadoop \
   && rm -rf ${HADOOP_HOME}/share/doc \
   && find /opt/ -name *-sources.jar -delete
ENV PATH="${HADOOP_HOME}/bin:${PATH}"
ENV HADOOP_CONF_DIR "${HADOOP_HOME}/etc/hadoop"
ENV LD_LIBRARY_PATH="${HADOOP_HOME}/lib/native:${LD_LIBRARY_PATH}"

# Anaconda
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" 

ARG PYTHON_VERSION=3.9
ARG CONDA_MIRROR=https://github.com/conda-forge/miniforge/releases/latest/download

WORKDIR /tmp

RUN set -x && \
    # Miniforge installer
    miniforge_arch=$(uname -m) && \
    miniforge_installer="Mambaforge-Linux-${miniforge_arch}.sh" && \
    wget --quiet "${CONDA_MIRROR}/${miniforge_installer}" && \
    /bin/bash "${miniforge_installer}" -f -b -p "${CONDA_DIR}" && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [[ "${PYTHON_VERSION}" != "default" ]]; then mamba install --quiet --yes python="${PYTHON_VERSION}"; fi && \
    # Pin major.minor version of python
    mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
    # Using conda to update all packages: https://github.com/mamba-org/mamba/issues/1092
    conda update --all --quiet --yes && \
    conda clean --all -f -y  

# Apache Spark 3.2.1
# ./dev/make-distribution.sh --name without-hadoop --pip --tgz -Phive -Phive-thriftserver -Pkubernetes -DskipTests -Phadoop-provided 
COPY spark-3.2.1-bin-without-hadoop.tgz /opt
RUN rm -rf ${SPARK_HOME}/ \
    && cd /opt \
    # && curl -sL --retry 3 "${ARCHIVE_URL}/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-without-hadoop.tgz" | tar xz  \
    && tar zxvf spark-${SPARK_VERSION}-bin-without-hadoop.tgz \
    && mv spark-${SPARK_VERSION}-bin-without-hadoop spark-${SPARK_VERSION} \
    && chown -R root:root spark-${SPARK_VERSION} \
    && ln -sfn spark-${SPARK_VERSION} spark \
    && mkdir -p ${SPARK_HOME}/conf-org/ \
    && mv ${SPARK_HOME}/conf/spark-env.sh.template ${SPARK_HOME}/conf-org/spark-env.sh \
    && rm -rf ${SPARK_HOME}/examples  ${SPARK_HOME}/data ${SPARK_HOME}/tests ${SPARK_HOME}/conf  \
    && echo 'export SPARK_DIST_CLASSPATH=$(hadoop classpath):/opt/hadoop/share/hadoop/tools/*:/opt/hadoop/share/hadoop/tools/lib/*' >> ${SPARK_HOME}/conf-org/spark-env.sh \
    && echo 'export SPARK_EXTRA_CLASSPATH=$(hadoop classpath):/opt/hadoop/share/hadoop/tools/*:/opt/hadoop/share/hadoop/tools/lib/*' >> ${SPARK_HOME}/conf-org/spark-env.sh

ENV PATH="${SPARK_HOME}/bin:${PATH}"

RUN sed -i '30i #CUSTOM\n' /opt/entrypoint.sh \
    && sed -i '/#CUSTOM/a source ${SPARK_HOME}/conf-org/spark-env.sh\n' /opt/entrypoint.sh

## Install Delta Lake
ENV SCALA_VERSION 2.12
ENV DELTA_LAKE_VERSION 2.0.0
ADD https://repo1.maven.org/maven2/io/delta/delta-core_${SCALA_VERSION}/${DELTA_LAKE_VERSION}/delta-core_${SCALA_VERSION}-${DELTA_LAKE_VERSION}.jar /opt/spark/jars
ADD https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_LAKE_VERSION}/delta-storage-${DELTA_LAKE_VERSION}.jar /opt/spark/jars
RUN chmod 644 /opt/spark/jars/delta-core_${SCALA_VERSION}-${DELTA_LAKE_VERSION}.jar
RUN chmod 644 /opt/spark/jars/delta-storage-${DELTA_LAKE_VERSION}.jar

## Install MSSQL java client
ENV MSSQL 1.2.0
ADD https://repo1.maven.org/maven2/com/microsoft/azure/spark-mssql-connector_2.12/${MSSQL}/spark-mssql-connector_2.12-${MSSQL}.jar /opt/spark/jars
# ADD https://repo1.maven.org/maven2/org/apache/hive/hive-metastore/${HIVE_METASTORE}/hive-metastore-${HIVE_METASTORE}.jar /opt/spark/jars
# ADD https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/${MARIADB}/mariadb-java-client-${MARIADB}.jar /opt/spark/jars
RUN chmod 644 /opt/spark/jars/spark-mssql-connector_2.12-${MSSQL}.jar
# RUN chmod 644 /opt/spark/jars/hive-metastore-${HIVE_METASTORE}.jar
# RUN chmod 644 /opt/spark/jars/mariadb-java-client-${MARIADB}.jar

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

RUN pip3 install delta-spark==${DELTA_LAKE_VERSION} timer

ENTRYPOINT ["/opt/entrypoint.sh"]
