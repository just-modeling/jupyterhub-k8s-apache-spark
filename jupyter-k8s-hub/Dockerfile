FROM jupyterhub/k8s-hub:1.2.0

USER root
RUN pip3 install --no-cache-dir -U \
    PyJWT

USER ${NB_USER}