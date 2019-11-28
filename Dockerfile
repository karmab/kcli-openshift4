FROM karmab/kcli
MAINTAINER Karim Boumedhel <karimboumedhel@gmail.com>
RUN apk add libc6-compat
ADD . /
ENTRYPOINT ["python3", "/run.py"]
CMD ["-h"]
