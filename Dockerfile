FROM karmab/kcli
MAINTAINER Karim Boumedhel <karimboumedhel@gmail.com>
RUN apk add libc6-compat
ADD . /
ENTRYPOINT ["python3", "/kcli-openshift4"]
CMD ["-h"]
