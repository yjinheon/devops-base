FROM jenkins/jenkins:lts

USER root

# install docker
RUN apt-get update && \
  apt-get -y install apt-transport-https \
  ca-certificates \
  curl \
  gnupg2 \
  zip \
  unzip \
  software-properties-common && \
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg > /tmp/dkey; apt-key add /tmp/dkey && \
  add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
  $(lsb_release -cs) \
  stable" && \
  apt-get update && \
  apt-get -y install docker-ce
RUN echo "Hello World"
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean:1.27.9"
