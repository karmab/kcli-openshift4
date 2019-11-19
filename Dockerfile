FROM karmab/kcli
MAINTAINER Karim Boumedhel <karimboumedhel@gmail.com>
ADD . /
ENTRYPOINT ["python3", "/run.py"]
CMD ["-h"]
