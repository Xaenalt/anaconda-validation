FROM registry.access.redhat.com/ubi8

RUN mkdir /validation && \
curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar -zxv -C /bin

WORKDIR /validation

COPY imagestream.yaml validate.sh /validation/

CMD ./validate.sh
